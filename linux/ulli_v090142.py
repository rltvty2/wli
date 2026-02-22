#!/usr/bin/env python3
"""
Linux-to-Linux Installer
A GUI tool to install a second Linux distribution alongside an existing one.

Supported targets: Linux Mint 22.3, Ubuntu 24.04.4, Kubuntu 24.04.4,
                   Debian Live 13.3.0 KDE, Fedora 43 KDE

Filesystem strategy:
  - btrfs:  Shrink the existing partition and install into new unallocated space

Requirements:
  pip3 install requests
  sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-vte-2.91 parted btrfs-progs \
                   grub-common grub2-common
"""

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Vte", "2.91")
from gi.repository import Gtk, Gdk, GLib, Pango, Vte

import os, sys, subprocess, threading, hashlib, shutil, json, time, signal
from pathlib import Path
from datetime import datetime

# ─── constants ───────────────────────────────────────────────────────────────

MIN_BOOT_GB   = 7
MIN_LINUX_GB  = 20

DISTROS = {
    "mint": {
        "label":    "Linux Mint 22.3 \"Zena\" – Cinnamon  (~2.9 GB)",
        "filename": "linuxmint-22.3-cinnamon-64bit.iso",
        "sha256":   "a081ab202cfda17f6924128dbd2de8b63518ac0531bcfe3f1a1b88097c459bd4",
        "size_gb":  2.9,
        "mirrors": [
            "https://mirrors.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso",
            "https://mirror.csclub.uwaterloo.ca/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso",
            "https://mirrors.seas.harvard.edu/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso",
        ],
        "live_path": "casper/vmlinuz",
    },
    "ubuntu": {
        "label":    "Ubuntu 24.04.4 LTS – GNOME  (~5.9 GB)",
        "filename": "ubuntu-24.04.4-desktop-amd64.iso",
        "sha256":   "3a4c9877b483ab46d7c3fbe165a0db275e1ae3cfe56a5657e5a47c2f99a99d1e",
        "size_gb":  5.9,
        "mirrors": [
            "https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-desktop-amd64.iso",
            "https://mirror.cs.uchicago.edu/ubuntu-releases/24.04.4/ubuntu-24.04.4-desktop-amd64.iso",
            "https://mirrors.mit.edu/ubuntu-releases/24.04.4/ubuntu-24.04.4-desktop-amd64.iso",
        ],
        "live_path": "casper/vmlinuz",
    },
    "kubuntu": {
        "label":    "Kubuntu 24.04.4 LTS – KDE Plasma  (~4.2 GB)",
        "filename": "kubuntu-24.04.4-desktop-amd64.iso",
        "sha256":   "02cda2568cb96c090b0438a31a7d2e7b07357fde16217c215e7c3f45263bcc49",
        "size_gb":  4.2,
        "mirrors": [
            "https://cdimage.ubuntu.com/kubuntu/releases/24.04.4/release/kubuntu-24.04.4-desktop-amd64.iso",
            "https://ftpmirror.your.org/pub/ubuntu/cdimage/kubuntu/releases/24.04/release/kubuntu-24.04.4-desktop-amd64.iso",
        ],
        "live_path": "casper/vmlinuz",
    },
    "debian": {
        "label":    "Debian Live 13.3.0 – KDE  (~3.2 GB)",
        "filename": "debian-live-13.3.0-amd64-kde.iso",
        "sha256":   "6a162340bca02edf67e159c847cd605618a77d50bf82088ee514f83369e43b89",
        "size_gb":  3.2,
        "mirrors": [
            "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.3.0-amd64-kde.iso",
            "https://mirrors.kernel.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.3.0-amd64-kde.iso",
        ],
        "live_path": "live/vmlinuz",
    },
    "fedora": {
        "label":    "Fedora 43 – KDE Plasma Desktop  (~3.0 GB)",
        "filename": "Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso",
        "sha256":   "181fe3e265fb5850c929f5afb7bdca91bb433b570ef39ece4a7076187435fdab",
        "size_gb":  3.0,
        "mirrors": [
            "https://d2lzkl7pfhq30w.cloudfront.net/pub/fedora/linux/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso",
            "https://mirror.web-ster.com/fedora/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso",
        ],
        "live_path": "LiveOS/squashfs.img",
        "hybrid": True,
    },
}

# ─── helpers ─────────────────────────────────────────────────────────────────

def run(cmd, **kw):
    """Run a command, return (returncode, stdout, stderr)."""
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    r = subprocess.run(cmd, **kw)
    out = r.stdout.strip() if r.stdout else ""
    err = r.stderr.strip() if r.stderr else ""
    return r.returncode, out, err

def run_root(cmd, **kw):
    """Run a command with pkexec (GUI sudo)."""
    return run(["pkexec", "--disable-internal-agent"] + cmd, **kw)

def get_root_fs_info():
    """Return dict with device, fstype, mountpoint for /."""
    code, out, _ = run(["findmnt", "-n", "-o", "SOURCE,FSTYPE,TARGET", "/"])
    if code != 0:
        return None
    parts = out.split()
    if len(parts) < 3:
        return None
    device = parts[0]
    # Strip btrfs subvolume suffix like [/@] or [/@home]
    if "[" in device:
        device = device.split("[")[0]
    return {"device": device, "fstype": parts[1], "mountpoint": parts[2]}

def get_partition_info(device):
    """Return size_bytes, free_bytes for the filesystem on device."""
    # Strip btrfs subvolume suffix like [/@] from device path
    clean_dev = device.split("[")[0] if "[" in device else device
    code, out, _ = run(["df", "--block-size=1", "--output=size,avail", clean_dev])
    if code != 0:
        # Fallback: try using the mountpoint instead
        code, out, _ = run(["df", "--block-size=1", "--output=size,avail", "/"])
        if code != 0:
            return None, None
    # Keep only lines that look like numbers (skip header)
    lines = []
    for l in out.strip().splitlines():
        parts = l.split()
        if parts and parts[0].isdigit():
            lines.append(l)
    if not lines:
        return None, None
    vals = lines[-1].split()
    return int(vals[0]), int(vals[1])

def bytes_to_gb(b):
    return round(b / 1e9, 2)

def sha256_file(path, progress_cb=None):
    h = hashlib.sha256()
    size = os.path.getsize(path)
    done = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
            done += len(chunk)
            if progress_cb:
                progress_cb(done / size)
    return h.hexdigest()

def iso_cache_dir():
    d = Path.home() / ".cache" / "linux-installer"
    d.mkdir(parents=True, exist_ok=True)
    return d

# ─── application ─────────────────────────────────────────────────────────────

class InstallerApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.linux.installer")
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        win = InstallerWindow(application=app)
        win.present()


class InstallerWindow(Gtk.ApplicationWindow):
    # ── init ──────────────────────────────────────────────────────────────────
    def __init__(self, **kw):
        super().__init__(title="ULLI USB-less Linux Installer", **kw)
        self.set_default_size(760, 820)
        self.set_resizable(False)

        self.selected_distro = "mint"
        self.custom_iso_path = ""
        self.fs_info = None
        self.running = False
        self.cancel_restart = False

        self._apply_css()
        self._build_ui()
        self.show_all()
        GLib.idle_add(self._refresh_disk_info)

    # ── CSS ───────────────────────────────────────────────────────────────────
    def _apply_css(self):
        css = b"""
        window { background-color: #1a1d21; }
        * { color: #c8cdd8; }
        label { color: #c8cdd8; }
        checkbutton label, radiobutton label { color: #c8cdd8; }
        entry { background-color: #2e333d; color: #c8cdd8; border-color: #3d4350; }
        spinbutton { background-color: #2e333d; color: #c8cdd8; border-color: #3d4350; }
        separator { background-color: #2e333d; }
        .header-title {
            font-family: 'IBM Plex Mono', 'Fira Mono', monospace;
            font-size: 22px; font-weight: 700;
            color: #87b94a; letter-spacing: -0.5px;
        }
        .sub-header { font-size: 11px; color: #5a6070; font-family: monospace; }
        .group-box {
            background-color: #22262d;
            border-radius: 8px;
            border: 1px solid #2e333d;
        }
        .group-label {
            font-family: 'IBM Plex Mono', monospace;
            font-size: 11px; font-weight: 700;
            color: #87b94a; letter-spacing: 1px;
            
        }
        .distro-radio {
            font-family: 'IBM Plex Mono', monospace;
            font-size: 12px; color: #c8cdd8;
        }
        .distro-radio:checked { color: #87b94a; }
        .disk-info { font-family: monospace; font-size: 11px; color: #8892a4; }
        .fs-btrfs { color: #5bc8f5; font-weight: bold; }
        .fs-other { color: #aaaaaa; }
        .log-box {
            font-family: 'Fira Code', 'Cascadia Code', monospace;
            font-size: 11px; background-color: #ffffff; color: #000000;
        }
        .log-box text { color: #000000; background-color: #ffffff; }
        .btn-start {
            background-color: #87b94a; color: #0d0f12;
            font-family: 'IBM Plex Mono', monospace;
            font-weight: 700; font-size: 13px;
            border-radius: 6px; border: none; padding: 8px 20px;
        }
        .btn-start:hover  { background-color: #9dce5f; }
        .btn-start:active { background-color: #6fa038; }
        .btn-exit {
            background-color: #2e333d; color: #8892a4;
            font-family: 'IBM Plex Mono', monospace;
            font-size: 12px; border-radius: 6px;
            border: 1px solid #3d4350; padding: 8px 20px;
        }
        .btn-exit:hover { background-color: #3d4350; color: #c8cdd8; }
        .progress-bar { min-height: 6px; }
        .progress-bar trough { background-color: #1a1d21; border-radius: 3px; }
        .progress-bar progress { background-color: #87b94a; border-radius: 3px; }
        .strategy-label {
            font-family: monospace; font-size: 11px;
            padding: 4px 8px; border-radius: 4px;
        }
        .strategy-btrfs { background-color: #1a3040; color: #5bc8f5; }
        .strategy-none  { background-color: #2a2a2a; color: #888888; }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    # ── UI construction ───────────────────────────────────────────────────────
    def _build_ui(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.set_margin_start(16); root.set_margin_end(16)
        root.set_margin_top(16);   root.set_margin_bottom(16)
        self.add(root)

        # ── Header ──
        hdr = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label(label="⚙ ULLI USB-less Linux Installer")
        title.get_style_context().add_class("header-title")
        sub = Gtk.Label(label="Dual-boot installer  ·  btrfs shrink  ·  no USB required")
        sub.get_style_context().add_class("sub-header")
        hdr.pack_start(title, False, False, 0)
        hdr.pack_start(sub, False, False, 0)
        root.pack_start(hdr, False, False, 8)

        # Status + progress
        self.status_label = Gtk.Label(label="Ready")
        self.status_label.get_style_context().add_class("sub-header")
        root.pack_start(self.status_label, False, False, 4)

        self.progress = Gtk.ProgressBar()
        self.progress.get_style_context().add_class("progress-bar")
        root.pack_start(self.progress, False, False, 4)

        # ── Distribution group ──
        root.pack_start(self._build_distro_group(), False, False, 8)

        # ── Disk info + size ──
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.pack_start(self._build_disk_group(), True, True, 0)
        row.pack_start(self._build_size_group(), True, True, 0)
        root.pack_start(row, False, False, 0)

        # ── Log ──
        root.pack_start(self._build_log_group(), True, True, 10)

        # ── Bottom bar ──
        root.pack_start(self._build_bottom_bar(), False, False, 0)

    def _group_frame(self, title):
        """Return (outer_box, inner_box)."""
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        outer.get_style_context().add_class("group-box")
        outer.set_margin_bottom(2)

        lbl = Gtk.Label(label=title, xalign=0)
        lbl.get_style_context().add_class("group-label")
        lbl.set_margin_start(12); lbl.set_margin_top(8)
        outer.pack_start(lbl, False, False, 0)

        sep = Gtk.Separator()
        sep.set_margin_start(8); sep.set_margin_end(8)
        outer.pack_start(sep, False, False, 0)

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        inner.set_margin_start(12); inner.set_margin_end(12)
        inner.set_margin_bottom(12); inner.set_margin_top(4)
        outer.pack_start(inner, True, True, 0)
        return outer, inner

    def _build_distro_group(self):
        outer, inner = self._group_frame("DISTRIBUTION")
        self.distro_radios = {}
        first_btn = None
        for key, info in DISTROS.items():
            btn = Gtk.RadioButton.new_with_label_from_widget(first_btn, info["label"])
            btn.get_style_context().add_class("distro-radio")
            btn.connect("toggled", self._on_distro_toggled, key)
            inner.pack_start(btn, False, False, 2)
            self.distro_radios[key] = btn
            if first_btn is None:
                first_btn = btn
        first_btn.set_active(True)

        sep = Gtk.Separator(); inner.pack_start(sep, False, False, 4)

        # Custom ISO row
        custom_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.custom_check = Gtk.CheckButton(label="Use existing ISO:")
        self.custom_check.connect("toggled", self._on_custom_toggled)
        custom_row.pack_start(self.custom_check, False, False, 0)
        self.custom_entry = Gtk.Entry(); self.custom_entry.set_sensitive(False)
        self.custom_entry.set_hexpand(True)
        custom_row.pack_start(self.custom_entry, True, True, 0)
        self.browse_btn = Gtk.Button(label="Browse…"); self.browse_btn.set_sensitive(False)
        self.browse_btn.connect("clicked", self._on_browse)
        custom_row.pack_start(self.browse_btn, False, False, 0)
        inner.pack_start(custom_row, False, False, 2)

        return outer

    def _build_disk_group(self):
        outer, inner = self._group_frame("DISK INFORMATION")
        self.disk_info_label = Gtk.Label(xalign=0)
        self.disk_info_label.get_style_context().add_class("disk-info")
        self.disk_info_label.set_line_wrap(True)
        inner.pack_start(self.disk_info_label, False, False, 0)

        self.strategy_label = Gtk.Label(label="Detecting filesystem…", xalign=0)
        self.strategy_label.get_style_context().add_class("strategy-label")
        self.strategy_label.get_style_context().add_class("strategy-none")
        inner.pack_start(self.strategy_label, False, False, 4)
        return outer

    def _build_size_group(self):
        outer, inner = self._group_frame("PARTITION / IMAGE SIZE")

        desc = Gtk.Label(xalign=0, wrap=True)
        desc.set_markup(
            '<span font_family="monospace" size="small" foreground="#8892a4">'
            "btrfs → shrinks partition, installs to new space"
            "</span>"
        )
        inner.pack_start(desc, False, False, 4)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lbl = Gtk.Label(label="Linux size (GB):", xalign=0)
        lbl.get_style_context().add_class("disk-info")
        row.pack_start(lbl, False, False, 0)
        adj = Gtk.Adjustment(value=30, lower=MIN_LINUX_GB, upper=500,
                             step_increment=5, page_increment=20)
        self.size_spin = Gtk.SpinButton(adjustment=adj, climb_rate=1, digits=0)
        row.pack_start(self.size_spin, False, False, 0)
        inner.pack_start(row, False, False, 4)

        self.size_help = Gtk.Label(
            label="Minimum 20 GB · Recommended 60+ GB", xalign=0)
        self.size_help.get_style_context().add_class("disk-info")
        inner.pack_start(self.size_help, False, False, 0)
        return outer

    def _build_log_group(self):
        outer, inner = self._group_frame("INSTALLATION LOG")
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(200)
        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False); self.log_view.set_cursor_visible(False)
        self.log_view.get_style_context().add_class("log-box")
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.log_buf = self.log_view.get_buffer()
        scroll.add(self.log_view)
        inner.pack_start(scroll, True, True, 0)
        return outer

    def _build_bottom_bar(self):
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.delete_check = Gtk.CheckButton(label="Delete ISO after installation")
        left.pack_start(self.delete_check, False, False, 0)
        self.restart_check = Gtk.CheckButton(label="Update GRUB and restart")
        self.restart_check.set_active(True)
        left.pack_start(self.restart_check, False, False, 0)
        bar.pack_start(left, True, True, 0)

        self.start_btn = Gtk.Button(label="▶  Start Installation")
        self.start_btn.get_style_context().add_class("btn-start")
        self.start_btn.connect("clicked", self._on_start)
        bar.pack_start(self.start_btn, False, False, 0)

        exit_btn = Gtk.Button(label="Exit")
        exit_btn.get_style_context().add_class("btn-exit")
        exit_btn.connect("clicked", lambda _: self.get_application().quit())
        bar.pack_start(exit_btn, False, False, 0)

        return bar

    # ── signal handlers ───────────────────────────────────────────────────────
    def _on_distro_toggled(self, btn, key):
        if btn.get_active():
            self.selected_distro = key

    def _on_custom_toggled(self, btn):
        on = btn.get_active()
        self.custom_entry.set_sensitive(on)
        self.browse_btn.set_sensitive(on)
        for r in self.distro_radios.values():
            r.set_sensitive(not on)

    def _on_browse(self, _btn):
        dlg = Gtk.FileChooserDialog(
            title="Select ISO file", parent=self,
            action=Gtk.FileChooserAction.OPEN)
        dlg.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                        Gtk.STOCK_OPEN,   Gtk.ResponseType.OK)
        f = Gtk.FileFilter(); f.set_name("ISO files"); f.add_pattern("*.iso")
        dlg.add_filter(f)
        if dlg.run() == Gtk.ResponseType.OK:
            self.custom_iso_path = dlg.get_filename()
            self.custom_entry.set_text(self.custom_iso_path)
        dlg.destroy()

    def _on_start(self, _btn):
        if self.running:
            return
        t = threading.Thread(target=self._run_install, daemon=True)
        t.start()

    # ── disk info ─────────────────────────────────────────────────────────────
    def _refresh_disk_info(self):
        self.fs_info = get_root_fs_info()
        if not self.fs_info:
            self._ui_set_disk_info("Could not detect root filesystem", None, None)
            return

        dev = self.fs_info["device"]
        fstype = self.fs_info["fstype"]
        total, free = get_partition_info(dev)

        total_gb = bytes_to_gb(total) if total else "?"
        free_gb  = bytes_to_gb(free)  if free  else "?"

        text = (
            f"Device:     {dev}\n"
            f"Filesystem: {fstype}\n"
            f"Total:      {total_gb} GB\n"
            f"Free:       {free_gb} GB\n"
            f"Mountpoint: {self.fs_info['mountpoint']}"
        )

        if fstype == "btrfs":
            strat = "STRATEGY: shrink btrfs → install to new partition"
            sc = "strategy-btrfs"
        else:
            strat = f"WARNING: unsupported filesystem ({fstype}) – only btrfs is supported"
            sc = "strategy-none"

        self._ui_set_disk_info(text, strat, sc)
        if free and total:
            max_gb = int(bytes_to_gb(free) - 15)
            if max_gb > MIN_LINUX_GB:
                self.size_spin.get_adjustment().set_upper(max_gb)

    def _ui_set_disk_info(self, text, strat, style_class):
        self.disk_info_label.set_text(text)
        ctx = self.strategy_label.get_style_context()
        for c in ["strategy-btrfs", "strategy-none"]:
            ctx.remove_class(c)
        if strat:
            self.strategy_label.set_text(strat)
            if style_class:
                ctx.add_class(style_class)

    # ── logging ───────────────────────────────────────────────────────────────
    def log(self, msg, error=False):
        ts = datetime.now().strftime("%H:%M:%S")
        line = f"[{ts}] {msg}\n"
        def _append():
            end = self.log_buf.get_end_iter()
            self.log_buf.insert(end, line)
            self.log_view.scroll_to_iter(self.log_buf.get_end_iter(), 0, False, 0, 0)
        GLib.idle_add(_append)
        if error:
            print(f"\033[31m{line}\033[0m", end="", file=sys.stderr)
        else:
            print(line, end="")

    def set_status(self, msg):
        GLib.idle_add(self.status_label.set_text, msg)

    def set_progress(self, frac):
        GLib.idle_add(self.progress.set_fraction, min(1.0, max(0.0, frac)))

    def pulse(self):
        GLib.idle_add(self.progress.pulse)

    # ── installation entry point ───────────────────────────────────────────────
    def _run_install(self):
        self.running = True
        GLib.idle_add(self.start_btn.set_sensitive, False)

        try:
            self._do_install()
        except Exception as e:
            self.log(f"FATAL ERROR: {e}", error=True)
            self.set_status("Installation failed!")
        finally:
            self.running = False
            GLib.idle_add(self.start_btn.set_sensitive, True)
            GLib.idle_add(self.set_progress, 0)

    def _do_install(self):
        self.log("=" * 52)
        self.log("Linux Live Installer starting")
        self.log("=" * 52)

        # ── 0. root check ──────────────────────────────────────────────────
        if os.geteuid() != 0:
            self.log("ERROR: installer must be run as root (sudo).", error=True)
            self.log("Re-launch with:  sudo python3 linux_installer.py", error=True)
            self.set_status("Please restart as root (sudo).")
            return

        # ── 1. gather info ─────────────────────────────────────────────────
        self.fs_info = get_root_fs_info()
        if not self.fs_info:
            self.log("Cannot detect root filesystem.", error=True)
            return

        fstype  = self.fs_info["fstype"]
        device  = self.fs_info["device"]
        linux_gb = int(self.size_spin.get_value())
        distro_key  = self.selected_distro
        custom_mode = self.custom_check.get_active()
        distro = DISTROS[distro_key]

        self.log(f"Root device : {device}")
        self.log(f"Filesystem  : {fstype}")
        self.log(f"Target size : {linux_gb} GB")
        self.log(f"Distro      : {distro['label']}")

        # ── 2. resolve ISO ─────────────────────────────────────────────────
        if custom_mode:
            iso_path = self.custom_iso_path
            if not iso_path or not os.path.exists(iso_path):
                self.log("No valid ISO selected.", error=True)
                return
            self.log(f"Custom ISO: {iso_path}")
        else:
            iso_path = str(iso_cache_dir() / distro["filename"])
            if os.path.exists(iso_path):
                sz = os.path.getsize(iso_path)
                self.log(f"Found cached ISO ({bytes_to_gb(sz)} GB): {iso_path}")
                ok = self._verify_checksum(iso_path, distro["sha256"])
                if not ok:
                    self.log("Checksum mismatch – deleting and re-downloading.", error=True)
                    os.unlink(iso_path)
                    if not self._download_iso(distro, iso_path):
                        return
            else:
                if not self._download_iso(distro, iso_path):
                    return

        # ── 3. choose strategy ──────────────────────────────────────────────
        self._boot_part_dev = None  # set by strategy if applicable
        if fstype == "btrfs":
            ok = self._strategy_btrfs(device, linux_gb, iso_path, distro, distro_key, custom_mode)
        else:
            self.log(f"Unsupported filesystem: {fstype}", error=True)
            self.log("Only btrfs is currently supported.", error=True)
            return

        if not ok:
            self.log("Installation aborted.", error=True)
            return

        # ── 4. cleanup ─────────────────────────────────────────────────────
        if self.delete_check.get_active() and not custom_mode:
            try:
                os.unlink(iso_path)
                self.log("ISO file deleted.")
            except Exception as e:
                self.log(f"Could not delete ISO: {e}")

        # ── 5. set UEFI boot entry + update GRUB + restart ────────────────
        self._update_grub()
        if self._boot_part_dev:
            self._set_uefi_boot_entry(self._boot_part_dev, distro["label"])
        if self.restart_check.get_active():
            self._do_restart()

        self.set_status("Installation complete!")
        self.log("=" * 52)
        self.log("All done! Review the log above for any warnings.")
        self.log("=" * 52)

    # ── ISO download ──────────────────────────────────────────────────────────
    def _download_iso(self, distro, dest):
        import urllib.request, urllib.error

        for i, url in enumerate(distro["mirrors"]):
            host = url.split("/")[2]
            self.log(f"Trying mirror {i+1}/{len(distro['mirrors'])}: {host}")
            self.set_status(f"Connecting to {host}…")
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "linux-installer/1.0"})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    total = int(resp.headers.get("Content-Length", 0))
                    total_mb = round(total / 1e6, 1)
                    done = 0
                    with open(dest, "wb") as f:
                        while True:
                            chunk = resp.read(1 << 17)   # 128 KB
                            if not chunk:
                                break
                            f.write(chunk)
                            done += len(chunk)
                            if total:
                                frac = done / total
                                mb = round(done / 1e6, 1)
                                GLib.idle_add(self.progress.set_fraction, frac)
                                self.set_status(
                                    f"Downloading {frac*100:.0f}%  {mb} / {total_mb} MB")
                self.log(f"Download complete: {bytes_to_gb(os.path.getsize(dest))} GB")
                GLib.idle_add(self.progress.set_fraction, 0)

                # verify
                if not self._verify_checksum(dest, distro["sha256"]):
                    self.log("Checksum failed – trying next mirror.", error=True)
                    os.unlink(dest)
                    continue
                return True

            except Exception as e:
                self.log(f"Download error: {e}", error=True)
                if os.path.exists(dest):
                    os.unlink(dest)

        self.log("All download mirrors failed.", error=True)
        self.log(f"Please download manually and place at:\n  {dest}", error=True)
        return False

    def _verify_checksum(self, path, expected):
        self.log("Verifying SHA-256 checksum…")
        self.set_status("Verifying ISO integrity…")

        def progress_cb(frac):
            GLib.idle_add(self.progress.set_fraction, frac)
            self.set_status(f"Checksumming… {frac*100:.0f}%")

        actual = sha256_file(path, progress_cb)
        GLib.idle_add(self.progress.set_fraction, 0)
        if actual == expected:
            self.log("✓ Checksum OK")
            return True
        self.log(f"✗ Expected: {expected}", error=True)
        self.log(f"✗ Actual:   {actual}",   error=True)
        return False

    # ── btrfs strategy ────────────────────────────────────────────────────────
    def _strategy_btrfs(self, device, linux_gb, iso_path, distro, distro_key, custom_mode):
        """
        1. Shrink the btrfs filesystem to free space.
        2. Create a new primary partition in the freed space.
        3. Format it FAT32.
        4. Copy ISO contents onto it.
        5. Register a GRUB entry.
        """
        self.log("")
        self.log("━━ Strategy: btrfs shrink + new partition ━━")

        total_shrink_gb = linux_gb + MIN_BOOT_GB

        # ── get btrfs usage ──
        self.set_status("Querying btrfs filesystem usage…")
        code, out, err = run(["btrfs", "filesystem", "usage", "-b", "/"])
        if code != 0:
            self.log(f"btrfs usage failed: {err}", error=True)
            return False

        # parse "Device size" and top-level "Used" from btrfs usage output
        dev_size = used = 0
        for line in out.splitlines():
            stripped = line.strip()
            if stripped.startswith("Device size:"):
                dev_size = int(stripped.split(":")[1].strip().split()[0])
            elif stripped.startswith("Used:"):
                used = int(stripped.split(":")[1].strip().split()[0])

        free_bytes = dev_size - used
        needed_bytes = total_shrink_gb * 1_073_741_824
        safe_free = free_bytes - (10 * 1_073_741_824)  # keep 10 GB buffer

        self.log(f"btrfs device size : {bytes_to_gb(dev_size)} GB")
        self.log(f"btrfs used        : {bytes_to_gb(used)} GB")
        self.log(f"Available to shrink: {bytes_to_gb(safe_free)} GB")

        if safe_free < needed_bytes:
            self.log(
                f"Not enough space! Need {total_shrink_gb} GB, "
                f"have only {bytes_to_gb(safe_free)} GB safe to use.", error=True)
            return False

        new_fs_size_bytes = dev_size - needed_bytes
        self.log(f"Shrinking btrfs from {bytes_to_gb(dev_size)} GB "
                 f"to {bytes_to_gb(new_fs_size_bytes)} GB…")
        self.set_status("Shrinking btrfs filesystem (this may take a while)…")

        code, out, err = run(["btrfs", "filesystem", "resize",
                               str(new_fs_size_bytes), "/"])
        if code != 0:
            self.log(f"btrfs resize failed: {err}", error=True)
            self.log("TIP: try running 'btrfs balance start /' first to compact data.", error=True)
            return False
        self.log("btrfs filesystem shrunk successfully.")

        # ── find the parent disk and partition ──
        disk_dev, part_num = self._resolve_disk_and_part(device)
        if not disk_dev:
            self.log("Cannot resolve parent disk for partition.", error=True)
            return False

        self.log(f"Disk: {disk_dev}  Partition: {part_num}")

        # ── get partition layout ──
        code, out, _ = run(["parted", "-m", disk_dev, "unit", "MiB", "print"])
        part_start_mib = None
        part_end_mib = None
        disk_label = "gpt"  # default assumption
        disk_end_mib = None
        # Track next partition after ours to know the upper bound for new partitions
        next_part_start_mib = None
        for line in out.splitlines():
            cols = line.rstrip(";").split(":")
            # Disk info line (2nd line in -m output) contains the label and disk size
            if len(cols) >= 6 and cols[0] == disk_dev:
                disk_label = cols[5]  # "gpt" or "msdos"
                disk_end_mib = int(float(cols[1].replace("MiB", "")))
            if len(cols) >= 3 and cols[0].isdigit():
                pn = int(cols[0])
                if pn == part_num:
                    part_start_mib = int(float(cols[1].replace("MiB", "")))
                    part_end_mib = int(float(cols[2].replace("MiB", "")))
                elif pn > part_num and next_part_start_mib is None:
                    next_part_start_mib = int(float(cols[1].replace("MiB", "")))
        if part_end_mib is None or part_start_mib is None:
            self.log("Cannot determine partition boundaries.", error=True)
            return False

        is_gpt = "gpt" in disk_label.lower()

        # Calculate new partition size
        new_part_size_mib = part_end_mib - part_start_mib - total_shrink_gb * 1024
        if new_part_size_mib < 1:
            self.log("Calculated new partition size is too small!", error=True)
            return False

        # ── shrink the existing partition to match the shrunk filesystem ──
        new_part_end_mib = part_start_mib + new_part_size_mib
        self.log(f"Shrinking partition {part_num}: {part_start_mib}–{part_end_mib} → "
                 f"{part_start_mib}–{new_part_end_mib} MiB")
        self.set_status("Shrinking partition…")

        # Use sfdisk to resize — it's non-interactive and handles mounted
        # partitions without prompting (unlike parted resizepart).
        # 1 MiB = 2048 sectors (512-byte sectors).
        new_size_sectors = new_part_size_mib * 2048
        sfdisk_script = f"{part_num}: size={new_size_sectors}\n"

        self.log(f"sfdisk: resizing partition {part_num} to {new_part_size_mib} MiB "
                 f"({new_size_sectors} sectors)")
        result = subprocess.run(
            ["sfdisk", "--no-reread", "-N", str(part_num), disk_dev],
            input=sfdisk_script, capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.log(f"sfdisk resize failed: {result.stderr.strip()}", error=True)
            # Fallback: try parted with LANG=C to avoid locale issues
            self.log("Trying parted fallback…")
            env = os.environ.copy()
            env["LANG"] = "C"
            env["LC_ALL"] = "C"
            result2 = subprocess.run(
                ["parted", "---pretend-input-tty", "-s", "--", disk_dev,
                 "resizepart", str(part_num), f"{new_part_end_mib}MiB"],
                input="Yes\n", capture_output=True, text=True, env=env,
            )
            if result2.returncode != 0:
                self.log(f"Partition resize failed: {result2.stderr.strip()}", error=True)
                self.log("You may need to grow the btrfs filesystem back with: "
                         "btrfs filesystem resize max /", error=True)
                return False

        # Re-read partition table and get actual new end of partition
        run(["partprobe", disk_dev])
        time.sleep(2)

        code, out, _ = run(["parted", "-m", disk_dev, "unit", "MiB", "print"])
        actual_new_end = None
        for line in out.splitlines():
            cols = line.rstrip(";").split(":")
            if len(cols) >= 3 and cols[0].isdigit() and int(cols[0]) == part_num:
                actual_new_end = int(float(cols[2].replace("MiB", "")))
        if actual_new_end is None:
            self.log("Cannot read partition table after resize.", error=True)
            return False

        self.log(f"Partition {part_num} now ends at {actual_new_end} MiB.")

        # Calculate new partition positions from the ACTUAL end
        boot_part_start  = actual_new_end + 1
        boot_part_end    = boot_part_start + MIN_BOOT_GB * 1024
        linux_part_start = boot_part_end + 1

        # Determine the upper bound for the linux partition
        if next_part_start_mib is not None:
            linux_part_end = f"{next_part_start_mib - 1}MiB"
            self.log(f"Next partition starts at {next_part_start_mib} MiB, "
                     f"linux partition will end at {next_part_start_mib - 1} MiB")
        else:
            linux_part_end = "100%"

        self.log(f"Partition shrunk successfully.")

        # ── create new partitions in the freed space ──
        self.log(f"Creating boot partition  {boot_part_start}–{boot_part_end} MiB …")
        self.set_status("Creating boot partition…")

        if is_gpt:
            # GPT mkpart syntax: mkpart NAME fs-type start end
            mkpart_boot  = ["mkpart", "LINUX_LIVE", "fat32",
                            f"{boot_part_start}MiB", f"{boot_part_end}MiB"]
            mkpart_linux = ["mkpart", "linux", "ext4",
                            f"{linux_part_start}MiB", linux_part_end]
        else:
            # MBR mkpart syntax: mkpart primary [fs-type] start end
            mkpart_boot  = ["mkpart", "primary", "fat32",
                            f"{boot_part_start}MiB", f"{boot_part_end}MiB"]
            mkpart_linux = ["mkpart", "primary", "ext4",
                            f"{linux_part_start}MiB", linux_part_end]

        cmd = ["parted", "-s", "--", disk_dev] + mkpart_boot + mkpart_linux
        code, _, err = run(cmd)
        if code != 0:
            # Retry without fs-type hint
            self.log(f"parted mkpart: {err} – retrying without FS type hint", error=True)
            if is_gpt:
                mkpart_boot2  = ["mkpart", "LINUX_LIVE",
                                 f"{boot_part_start}MiB", f"{boot_part_end}MiB"]
                mkpart_linux2 = ["mkpart", "linux",
                                 f"{linux_part_start}MiB", linux_part_end]
            else:
                mkpart_boot2  = ["mkpart", "primary",
                                 f"{boot_part_start}MiB", f"{boot_part_end}MiB"]
                mkpart_linux2 = ["mkpart", "primary",
                                 f"{linux_part_start}MiB", linux_part_end]

            cmd2 = ["parted", "-s", "--", disk_dev] + mkpart_boot2 + mkpart_linux2
            code, _, err2 = run(cmd2)
            if code != 0:
                self.log(f"Cannot create partitions: {err2}", error=True)
                return False

        time.sleep(2)
        run(["partprobe", disk_dev])
        time.sleep(2)

        # Find newly created partitions by matching their start positions
        code, out, _ = run(["parted", "-m", disk_dev, "unit", "MiB", "print"])
        boot_part_num = None
        linux_part_num = None
        for line in out.splitlines():
            cols = line.rstrip(";").split(":")
            if len(cols) >= 3 and cols[0].isdigit():
                pn = int(cols[0])
                start = int(float(cols[1].replace("MiB", "")))
                # Match within 2 MiB tolerance
                if abs(start - boot_part_start) <= 2:
                    boot_part_num = pn
                elif abs(start - linux_part_start) <= 2:
                    linux_part_num = pn

        if boot_part_num is None or linux_part_num is None:
            self.log(f"Cannot identify new partitions (boot={boot_part_num}, "
                     f"linux={linux_part_num}). Expected starts: "
                     f"{boot_part_start}, {linux_part_start} MiB", error=True)
            self.log(f"Partition table:\n{out}")
            return False

        # Construct device paths (handle nvme naming: nvme0n1p8 vs sda8)
        if f"{disk_dev}p{boot_part_num}" in out or \
           os.path.exists(f"{disk_dev}p{boot_part_num}"):
            boot_part_dev  = f"{disk_dev}p{boot_part_num}"
            linux_part_dev = f"{disk_dev}p{linux_part_num}"
        else:
            boot_part_dev  = f"{disk_dev}{boot_part_num}"
            linux_part_dev = f"{disk_dev}{linux_part_num}"

        self.log(f"Boot partition  : {boot_part_dev}")
        self.log(f"Linux partition : {linux_part_dev} (unformatted – for installer)")

        # Format boot partition FAT32
        self.set_status("Formatting boot partition FAT32…")
        code, _, err = run(["mkfs.fat", "-F32", "-n", "LINUX_LIVE", boot_part_dev])
        if code != 0:
            self.log(f"mkfs.fat failed: {err}", error=True)
            return False

        # Mount and copy ISO
        mnt = "/mnt/linux_installer_boot"
        os.makedirs(mnt, exist_ok=True)
        run(["mount", boot_part_dev, mnt])
        try:
            ok = self._copy_iso_to_mount(iso_path, mnt, distro, distro_key)
        finally:
            run(["umount", mnt])

        if not ok:
            return False

        self.log(f"Boot partition ready at {boot_part_dev}.")
        self.log(f"Linux unallocated partition at {linux_part_dev} – "
                 "the installer will format this during installation.")

        self._boot_part_dev = boot_part_dev

        self._write_boot_instructions(
            boot_dev=boot_part_dev,
            linux_dev=linux_part_dev,
            distro_label=distro["label"],
        )
        return True

    # ── GRUB integration ──────────────────────────────────────────────────────
    def _copy_iso_to_mount(self, iso_path, mnt, distro, distro_key):
        """Mount ISO read-only and rsync its contents to mnt."""
        iso_mnt = "/mnt/linux_installer_iso_copy"
        os.makedirs(iso_mnt, exist_ok=True)

        hybrid = distro.get("hybrid", False)

        if not hybrid:
            code, _, err = run(["mount", "-o", "loop,ro", iso_path, iso_mnt])
            if code != 0:
                self.log(f"Cannot mount ISO: {err}", error=True)
                return False

        try:
            if hybrid:
                # For hybrid ISOs (Fedora), use 7z or isoinfo to extract
                self.log("Hybrid ISO detected – extracting with 7z…")
                code, _, err = run(["7z", "x", f"-o{mnt}", iso_path, "-y"],
                                   capture_output=False)
                if code not in (0, 1):
                    self.log(f"7z extraction failed ({code}): {err}", error=True)
                    return False
            else:
                self.log("Copying ISO contents to boot partition (10–20 min)…")
                self.set_status("Copying files…")
                code, _, err = run(
                    ["rsync", "-a", "--info=progress2", f"{iso_mnt}/", f"{mnt}/"],
                    capture_output=False)
                if code != 0:
                    self.log(f"rsync failed: {err}", error=True)
                    return False

            # Fix Fedora boot labels if needed
            if distro_key == "fedora":
                self._patch_fedora_labels(mnt, "LINUX_LIVE")

        finally:
            if not hybrid:
                run(["umount", iso_mnt])

        self.log("ISO contents copied.")
        return True

    def _patch_fedora_labels(self, mnt, label):
        self.log(f"Patching Fedora boot config labels → {label}")
        cfg_files = [
            f"{mnt}/EFI/BOOT/grub.cfg",
            f"{mnt}/boot/grub2/grub.cfg",
            f"{mnt}/isolinux/isolinux.cfg",
        ]
        import re
        for p in cfg_files:
            if not os.path.exists(p):
                continue
            with open(p, "r", errors="replace") as f:
                content = f.read()
            patched = re.sub(r"(root=live:(?:CD)?LABEL=)(\S+)", rf"\g<1>{label}", content)
            patched = re.sub(r"(set isolabel=)(\S+)", rf"\g<1>{label}", patched)
            if patched != content:
                with open(p, "w") as f:
                    f.write(patched)
                self.log(f"  Patched: {Path(p).name}")

    def _update_grub(self):
        self.log("Updating GRUB…")
        self.set_status("Running update-grub…")
        for cmd in [["update-grub"], ["grub2-mkconfig", "-o", "/boot/grub2/grub.cfg"]]:
            code, _, err = run(cmd)
            if code == 0:
                self.log("GRUB updated successfully.")
                return True
            if "not found" not in err and "No such file" not in err:
                self.log(f"GRUB update warning: {err}")

        self.log("Could not update GRUB automatically.", error=True)
        self.log("Run 'sudo update-grub' or 'sudo grub2-mkconfig -o /boot/grub2/grub.cfg' manually.")
        return False

    def _set_uefi_boot_entry(self, boot_part_dev, distro_label):
        """
        Create a UEFI boot entry for the live boot partition and set it
        as the first entry in the UEFI boot order using efibootmgr.
        """
        self.log("Configuring UEFI boot entry…")
        self.set_status("Setting UEFI boot order…")

        import re

        # Check if we're on a UEFI system
        if not os.path.isdir("/sys/firmware/efi"):
            self.log("System is not UEFI – skipping UEFI boot entry.")
            self.log("You may need to select the boot device manually from "
                     "your BIOS/legacy boot menu.")
            return

        # Check for efibootmgr
        if not shutil.which("efibootmgr"):
            self.log("efibootmgr not found. Install with: sudo apt install efibootmgr",
                     error=True)
            return

        # Resolve disk and partition number
        disk_dev, part_num = self._resolve_disk_and_part(boot_part_dev)
        if not disk_dev or not part_num:
            self.log(f"Cannot resolve disk/partition for {boot_part_dev}", error=True)
            return

        # Find the EFI bootloader on the boot partition
        mnt = "/mnt/linux_installer_efi_check"
        os.makedirs(mnt, exist_ok=True)
        code, _, _ = run(["mount", "-o", "ro", boot_part_dev, mnt])
        if code != 0:
            # It might already be mounted from the copy step
            code, mnt_out, _ = run(["findmnt", "-n", "-o", "TARGET", boot_part_dev])
            if code == 0 and mnt_out:
                mnt = mnt_out.strip()
            else:
                self.log("Cannot mount boot partition to find EFI loader.", error=True)
                return

        # Search for EFI bootloader files
        efi_loader = None
        efi_search_paths = [
            "EFI/BOOT/BOOTx64.EFI",
            "EFI/BOOT/bootx64.efi",
            "EFI/BOOT/grubx64.efi",
            "EFI/boot/BOOTx64.EFI",
            "EFI/boot/bootx64.efi",
        ]
        for rel_path in efi_search_paths:
            full = os.path.join(mnt, rel_path)
            if os.path.exists(full):
                # efibootmgr wants the path with backslashes
                efi_loader = "\\" + rel_path.replace("/", "\\")
                break

        # Also search case-insensitively
        if not efi_loader:
            efi_dir = os.path.join(mnt, "EFI")
            if os.path.isdir(efi_dir):
                for root, dirs, files in os.walk(efi_dir):
                    for f in files:
                        if f.lower().endswith(".efi"):
                            rel = os.path.relpath(os.path.join(root, f), mnt)
                            efi_loader = "\\" + rel.replace("/", "\\")
                            break
                    if efi_loader:
                        break

        run(["umount", mnt])

        if not efi_loader:
            self.log("No EFI bootloader found on the boot partition.", error=True)
            self.log("You may need to boot from the UEFI firmware menu manually.")
            return

        self.log(f"Found EFI loader: {efi_loader}")

        entry_name = distro_label.split("–")[0].strip().rstrip('"').strip()

        # Remove any existing entry with the same name to avoid duplicates
        code, efi_out, _ = run(["efibootmgr", "-v"])
        if code == 0:
            for line in efi_out.splitlines():
                if entry_name.lower() in line.lower():
                    m = re.match(r"Boot(\w{4})", line)
                    if m:
                        boot_num = m.group(1)
                        self.log(f"Removing existing UEFI entry Boot{boot_num}")
                        run(["efibootmgr", "-b", boot_num, "-B"])

        # Create new UEFI boot entry
        self.log(f"Creating UEFI boot entry: \"{entry_name}\"")
        self.log(f"  Disk: {disk_dev}  Partition: {part_num}  Loader: {efi_loader}")

        code, out, err = run([
            "efibootmgr", "--create",
            "--disk", disk_dev,
            "--part", str(part_num),
            "--label", entry_name,
            "--loader", efi_loader,
        ])
        if code != 0:
            self.log(f"efibootmgr --create failed: {err}", error=True)
            self.log("You may need to select the boot device from the UEFI firmware menu.")
            return

        # Extract the new boot entry number
        new_boot_num = None
        m = re.search(r"Boot(\w{4})\*?\s+" + re.escape(entry_name), out)
        if m:
            new_boot_num = m.group(1)

        if not new_boot_num:
            # Try to find it from the current entries
            code, efi_out, _ = run(["efibootmgr"])
            for line in efi_out.splitlines():
                if entry_name in line:
                    m = re.match(r"Boot(\w{4})", line)
                    if m:
                        new_boot_num = m.group(1)
                        break

        if new_boot_num:
            # Set as first in boot order
            code, efi_out, _ = run(["efibootmgr"])
            # Parse current BootOrder
            boot_order = ""
            for line in efi_out.splitlines():
                if line.startswith("BootOrder:"):
                    boot_order = line.split(":")[1].strip()
                    break

            # Put our entry first
            order_entries = [e.strip() for e in boot_order.split(",") if e.strip()]
            # Remove our entry if already in the list
            order_entries = [e for e in order_entries if e != new_boot_num]
            # Prepend it
            new_order = ",".join([new_boot_num] + order_entries)

            code, _, err = run(["efibootmgr", "-o", new_order])
            if code == 0:
                self.log(f"UEFI boot order set: {new_order}")
                self.log(f"Boot{new_boot_num} (\"{entry_name}\") is now the default.")
            else:
                self.log(f"Could not set boot order: {err}", error=True)
                self.log(f"Entry Boot{new_boot_num} was created but not set as default.")
        else:
            self.log("UEFI entry created but could not determine its boot number.")
            self.log("Check with: sudo efibootmgr -v")

        # Log final boot state
        code, efi_out, _ = run(["efibootmgr"])
        if code == 0:
            self.log("Current UEFI boot entries:")
            for line in efi_out.splitlines():
                self.log(f"  {line}")

    # ── helpers ───────────────────────────────────────────────────────────────
    def _resolve_disk_and_part(self, device):
        """Given /dev/sda3 return ('/dev/sda', 3), handles nvme too."""
        import re
        m = re.match(r"^(/dev/(?:nvme\d+n\d+|[a-z]+))p?(\d+)$", device)
        if m:
            return m.group(1), int(m.group(2))
        return None, None

    def _write_boot_instructions(self, boot_dev, linux_dev, distro_label):
        dest = Path.home() / "Desktop" / "Linux_Installer_Instructions.txt"
        body = f"""
Linux Installer – Boot Instructions
====================================
Strategy: btrfs partition shrink + new partition

Distro:          {distro_label}
Boot partition:  {boot_dev}  (FAT32, 7 GB – contains live ISO files)
Linux partition: {linux_dev}  (unformatted – installer will use this)

To boot the live environment:
  1. Restart your computer.
  2. Enter UEFI/BIOS (F2 / F10 / F12 / DEL / ESC at POST).
  3. Set Boot Order to prioritise: {boot_dev}
  4. Disable Secure Boot if enabled.
  5. Save & exit – the system boots into the live environment.

During installation the installer will auto-detect {linux_dev}
as free space and offer "Install alongside existing Linux".
"""
        try:
            dest.write_text(body)
            self.log(f"Instructions written to {dest}")
        except Exception:
            pass

    def _do_restart(self):
        self.log("Restarting in 15 seconds… (close this window to cancel)")
        self.set_status("Restarting in 15 seconds…")
        for i in range(15, 0, -1):
            if self.cancel_restart:
                self.log("Restart cancelled.")
                return
            self.set_status(f"Restarting in {i} seconds…")
            time.sleep(1)
        run(["reboot"])


# ─── entry point ──────────────────────────────────────────────────────────────

def check_deps():
    missing = []
    for tool in ["parted", "rsync", "mkfs.fat",
                 "btrfs", "blkid", "update-grub"]:
        if shutil.which(tool) is None:
            missing.append(tool)
    return missing


if __name__ == "__main__":
    if "--check-deps" in sys.argv:
        m = check_deps()
        if m:
            print("Missing tools:", ", ".join(m))
            print("Install with:")
            print("  sudo apt install " +
                  "parted rsync dosfstools btrfs-progs grub-common")
        else:
            print("All dependencies satisfied.")
        sys.exit(0)

    app = InstallerApp()
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    sys.exit(app.run(sys.argv))
