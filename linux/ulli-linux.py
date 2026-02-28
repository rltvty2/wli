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

import os, sys, subprocess, threading, hashlib, shutil, json, time, signal, re
import urllib.request, urllib.error
from pathlib import Path
from datetime import datetime

# ─── constants ───────────────────────────────────────────────────────────────

MIN_BOOT_GB   = 7
MIN_LINUX_GB  = 20
GiB           = 1_073_741_824

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

# ─── disk enumeration helpers ────────────────────────────────────────────────

def get_all_disks():
    """Return list of dicts with disk info: name, path, size_bytes, model, partitions."""
    code, out, _ = run(["lsblk", "-b", "-n", "-d", "-o", "NAME,SIZE,MODEL,TYPE", "--json"])
    if code != 0:
        # Fallback without JSON
        code, out, _ = run(["lsblk", "-b", "-n", "-d", "-o", "NAME,SIZE,MODEL,TYPE"])
        if code != 0:
            return []
        disks = []
        for line in out.splitlines():
            parts = line.split(None, 3)
            if len(parts) >= 4 and parts[3].strip() == "disk":
                disks.append({
                    "name": parts[0],
                    "path": f"/dev/{parts[0]}",
                    "size_bytes": int(parts[1]),
                    "model": parts[2] if len(parts) > 2 else "",
                })
        return disks

    data = json.loads(out)
    disks = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") != "disk":
            continue
        disks.append({
            "name": dev["name"],
            "path": f"/dev/{dev['name']}",
            "size_bytes": int(dev.get("size", 0)),
            "model": (dev.get("model") or "").strip(),
        })
    return disks


def get_disk_partitions(disk_path):
    """Return list of partition dicts from parted for a disk.
    Each dict has: num, start_mib, end_mib, size_mib, fstype, name, flags, is_free."""
    code, out, _ = run(["parted", "-m", disk_path, "unit", "MiB", "print", "free"])
    if code != 0:
        return [], "gpt", 0
    partitions = []
    disk_label = "gpt"
    disk_size_mib = 0
    for line in out.splitlines():
        line = line.rstrip(";").strip()
        if not line or line == "BYT":
            continue
        cols = line.split(":")

        # Disk info line: /dev/sdb:1907729MiB:scsi:512:4096:gpt:Samsung...
        if len(cols) >= 6 and cols[0] == disk_path:
            disk_label = cols[5]
            try:
                disk_size_mib = int(float(cols[1].replace("MiB", "")))
            except ValueError:
                pass
            continue

        # Skip lines that don't look like partition/free entries
        if len(cols) < 4:
            continue

        # Detect free space: the word "free" appears somewhere in the columns
        is_free = any(c.strip().lower() == "free" for c in cols)

        # Parse start/end/size from columns 1-3 (0-indexed)
        try:
            start_mib = int(float(cols[1].replace("MiB", "")))
            end_mib = int(float(cols[2].replace("MiB", "")))
            size_mib = int(float(cols[3].replace("MiB", "")))
        except (ValueError, IndexError):
            continue

        # Parse partition number (column 0) — free space entries may have a
        # number that's just a positional index, not a real partition number
        part_num = 0
        if not is_free and cols[0].isdigit():
            part_num = int(cols[0])

        entry = {
            "num": part_num,
            "start_mib": start_mib,
            "end_mib": end_mib,
            "size_mib": size_mib,
            "fstype": cols[4].strip() if len(cols) > 4 else "",
            "name": cols[5].strip() if len(cols) > 5 else "",
            "flags": cols[6].strip() if len(cols) > 6 else "",
            "is_free": is_free,
        }
        partitions.append(entry)
    return partitions, disk_label, disk_size_mib


def get_partition_fstype(dev_path):
    """Get filesystem type for a partition device (e.g. /dev/sdb1)."""
    code, out, _ = run(["blkid", "-o", "value", "-s", "TYPE", dev_path])
    if code == 0 and out.strip():
        return out.strip()
    return ""


def get_partition_usage(dev_path):
    """Get total and free bytes for a mounted or mountable partition."""
    # Check if mounted
    code, out, _ = run(["findmnt", "-n", "-o", "TARGET", dev_path])
    if code == 0 and out.strip():
        mountpoint = out.strip()
        code2, df_out, _ = run(["df", "--block-size=1", "--output=size,avail", mountpoint])
        if code2 == 0:
            for line in df_out.strip().splitlines():
                parts = line.split()
                if parts and parts[0].isdigit():
                    return int(parts[0]), int(parts[1])
    return None, None


def get_disk_unallocated_mib(disk_path):
    """Return total unallocated MiB on a disk."""
    parts, _, disk_size_mib = get_disk_partitions(disk_path)
    total = 0
    for p in parts:
        if p["is_free"] and p["size_mib"] > 1:
            total += p["size_mib"]
    # If parted didn't return free space entries, estimate from disk size
    # minus sum of partition sizes
    if total == 0 and disk_size_mib > 0:
        used = sum(p["size_mib"] for p in parts if not p["is_free"])
        gap = disk_size_mib - used
        if gap > 10:  # more than 10 MiB
            total = gap
    return total


def get_disk_layout_text(disk_path):
    """Return list of text lines describing partition layout of a disk."""
    parts, label, total_mib = get_disk_partitions(disk_path)
    lines = []
    if not parts:
        lines.append(f"  [Empty disk]  {round(total_mib / 1024, 2)} GB")
        return lines

    for p in parts:
        size_gb = round(p["size_mib"] / 1024, 2)
        if p["is_free"]:
            if size_gb > 0.01:
                lines.append(f"  [Unallocated]             {size_gb} GB")
            continue
        # Build label
        dev_path = _part_dev_path(disk_path, p["num"])
        fstype = get_partition_fstype(dev_path)
        name = p["name"] or ""
        flags = p["flags"] or ""

        if "boot" in flags or "esp" in flags:
            label_str = "EFI System (ESP)     "
        elif name:
            label_str = f"{name:<22}"
        elif fstype:
            label_str = f"Partition ({fstype:<8}) "
        else:
            label_str = "Partition            "

        # Check for mountpoint
        code, mnt_out, _ = run(["findmnt", "-n", "-o", "TARGET", dev_path])
        mount_info = ""
        if code == 0 and mnt_out.strip():
            mountpoint = mnt_out.strip()
            total, free = get_partition_usage(dev_path)
            if total and free:
                mount_info = f"  [mounted: {mountpoint}, Free: {round(free / 1e9, 2)} GB]"
            else:
                mount_info = f"  [mounted: {mountpoint}]"

        lines.append(f"  {label_str} {size_gb} GB{mount_info}")

    return lines


def _part_dev_path(disk_path, part_num):
    """Given /dev/sda and 3, return /dev/sda3. Handles nvme (/dev/nvme0n1p3)."""
    if "nvme" in disk_path or "mmcblk" in disk_path:
        return f"{disk_path}p{part_num}"
    return f"{disk_path}{part_num}"


def _parse_bytes_value(line):
    """Extract the integer before 'bytes' in a line like 'Current volume size: 123456 bytes'."""
    parts = line.split()
    for i, p in enumerate(parts):
        if p == "bytes" and i > 0:
            try:
                return int(parts[i - 1])
            except ValueError:
                pass
    return 0

def _ntfs_info(dev_path):
    """Query NTFS volume size and free space via ntfsresize --info.
    Returns (total_bytes, free_bytes) or (None, None)."""
    if not shutil.which("ntfsresize"):
        return None, None
    code, out, _ = run(["ntfsresize", "--info", "--force", dev_path])
    if code != 0:
        return None, None
    current_size = 0
    min_size = 0
    for line in out.splitlines():
        if "Current volume size" in line and "bytes" in line:
            current_size = _parse_bytes_value(line)
        elif "You might resize at" in line and "bytes" in line:
            min_size = _parse_bytes_value(line)
    if current_size > 0:
        free = current_size - min_size if min_size > 0 else current_size // 2
        return current_size, free
    return None, None

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
            background-color: #5a8a2a; color: #ffffff;
            font-family: 'IBM Plex Mono', monospace;
            font-weight: 700; font-size: 13px;
            border-radius: 6px; border: none; padding: 8px 20px;
        }
        .btn-start:hover  { background-color: #6fa038; }
        .btn-start:active { background-color: #4a7222; }
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
        .btn-browse { color: #000000; }
        .btn-browse label { color: #000000; }
        filechooser, filechooser * { color: #000000; background-color: #ffffff; }
        filechooser entry { color: #000000; background-color: #ffffff; }
        filechooser treeview { color: #000000; background-color: #ffffff; }
        filechooser treeview:selected,
        filechooser treeview row:selected,
        filechooser treeview:selected *,
        filechooser row:selected,
        filechooser row:selected * { background-color: #4a90d9; color: #ffffff; }
        filechooser treeview header button { color: #000000; }
        filechooser placesview { color: #000000; background-color: #f0f0f0; }
        filechooser placessidebar { color: #000000; background-color: #f0f0f0; }
        filechooser placessidebar label { color: #000000; }
        filechooser placessidebar row:selected,
        filechooser placessidebar row:selected * { background-color: #4a90d9; color: #ffffff; }
        filechooser button { color: #000000; }
        filechooser button label { color: #000000; }
        filechooser label { color: #000000; }
        filechooser .path-bar button label { color: #000000; }
        .dialog-action-area button label { color: #000000; }
        .disk-plan { background-color: #f5f5f5; }
        .disk-plan * { color: #1a1a1a; }
        .disk-plan label { color: #1a1a1a; }
        .disk-plan frame label { color: #333333; }
        .disk-plan radiobutton label { color: #1a1a1a; }
        .disk-plan textview, .disk-plan textview text {
            color: #000000; background-color: #ffffff;
        }
        .disk-plan combobox * { color: #1a1a1a; }
        .disk-plan button { color: #1a1a1a; }
        .disk-plan button label { color: #1a1a1a; }
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

        # Custom ISO row – radio button in same group as distro radios
        custom_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.custom_radio = Gtk.RadioButton.new_with_label_from_widget(first_btn, "Use existing ISO:")
        self.custom_radio.get_style_context().add_class("distro-radio")
        self.custom_radio.connect("toggled", self._on_custom_toggled)
        custom_row.pack_start(self.custom_radio, False, False, 0)
        self.custom_entry = Gtk.Entry(); self.custom_entry.set_sensitive(False)
        self.custom_entry.set_hexpand(True)
        custom_row.pack_start(self.custom_entry, True, True, 0)
        self.browse_btn = Gtk.Button(label="Browse…"); self.browse_btn.set_sensitive(False)
        self.browse_btn.get_style_context().add_class("btn-browse")
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
            self.custom_entry.set_tooltip_text(self.custom_iso_path)
            # Update radio label to show selected filename
            iso_name = os.path.basename(self.custom_iso_path)
            self.custom_radio.set_label(f"Use existing ISO:  {iso_name}")
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

    # ── disk plan dialog ────────────────────────────────────────────────────
    def _show_disk_plan(self, distro_label, linux_gb):
        """Show a GTK dialog with disk selection, before/after layout, strategy.
        Returns dict with approved, strategy, target_disk, shrink_dev, shrink_gb
        or None if cancelled. Must be called on the GTK main thread."""

        boot_gb = MIN_BOOT_GB
        total_needed_gb = linux_gb + boot_gb

        # Gather disk info
        all_disks = get_all_disks()
        root_info = self.fs_info
        root_dev = root_info["device"] if root_info else ""
        # Find which disk contains the root partition
        root_disk_path = ""
        if root_dev:
            disk_dev, _ = self._resolve_disk_and_part(root_dev)
            if disk_dev:
                root_disk_path = disk_dev

        # Build disk list
        disk_entries = []
        for d in all_disks:
            size_gb = round(d["size_bytes"] / 1e9, 1)
            free_mib = get_disk_unallocated_mib(d["path"])
            free_gb = round(free_mib / 1024, 1)
            is_root = (d["path"] == root_disk_path)
            prefix = f"{d['name']} (current OS)" if is_root else d["name"]
            model = d["model"] or "Disk"
            label = f"{prefix} – {model} – {size_gb} GB – Free: {free_gb} GB"
            disk_entries.append({
                "name": d["name"],
                "path": d["path"],
                "label": label,
                "is_root": is_root,
                "size_gb": size_gb,
                "free_gb": free_gb,
                "free_mib": free_mib,
            })

        # ── Build the dialog ──
        dialog = Gtk.Dialog(
            title="Disk Plan – Review Before Proceeding",
            transient_for=self,
            modal=True,
            destroy_with_parent=True,
        )
        dialog.set_default_size(700, 680)
        dialog.set_resizable(False)

        content = dialog.get_content_area()
        content.get_style_context().add_class("disk-plan")
        content.set_spacing(8)
        content.set_margin_start(16); content.set_margin_end(16)
        content.set_margin_top(12); content.set_margin_bottom(8)

        # Title
        title = Gtk.Label(label=f"Review Disk Changes for {distro_label}", xalign=0)
        title.set_markup(
            f'<span size="large" weight="bold" foreground="#1a1a1a">'
            f'Review Disk Changes for {distro_label}</span>')
        content.pack_start(title, False, False, 0)

        # Warning banner
        warn_box = Gtk.Box(spacing=6)
        warn_box.set_margin_top(4); warn_box.set_margin_bottom(4)
        warn_label = Gtk.Label(xalign=0, wrap=True)
        warn_label.set_markup(
            '<span foreground="#996600">⚠  These changes modify your disk\'s partition '
            'table. Some options (like wipe &amp; reformat) will DESTROY ALL DATA on the '
            'target disk. Make sure you have a backup of important files before proceeding.'
            '</span>')
        warn_box.pack_start(warn_label, True, True, 0)
        content.pack_start(warn_box, False, False, 0)

        # ── Target Disk selector ──
        disk_frame = Gtk.Frame(label="Target Disk")
        disk_combo = Gtk.ComboBoxText()
        root_index = 0
        for i, de in enumerate(disk_entries):
            disk_combo.append_text(de["label"])
            if de["is_root"]:
                root_index = i
        disk_combo.set_active(root_index)
        disk_frame.add(disk_combo)
        disk_frame.set_margin_top(4)
        content.pack_start(disk_frame, False, False, 0)

        # ── Current Layout ──
        layout_frame = Gtk.Frame(label="Current Disk Layout")
        layout_text = Gtk.TextView()
        layout_text.set_editable(False); layout_text.set_cursor_visible(False)
        layout_text.set_monospace(True)
        layout_text.set_wrap_mode(Gtk.WrapMode.NONE)
        layout_scroll = Gtk.ScrolledWindow()
        layout_scroll.set_min_content_height(120)
        layout_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        layout_scroll.add(layout_text)
        layout_frame.add(layout_scroll)
        content.pack_start(layout_frame, False, False, 0)

        # ── Strategy Selection ──
        strat_frame = Gtk.Frame(label="Installation Strategy")
        strat_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        strat_box.set_margin_start(8); strat_box.set_margin_end(8)
        strat_box.set_margin_top(4); strat_box.set_margin_bottom(4)
        radio_primary = Gtk.RadioButton.new_with_label(None, "")
        radio_secondary = Gtk.RadioButton.new_with_label_from_widget(radio_primary, "")
        radio_wipe = Gtk.RadioButton.new_with_label_from_widget(radio_primary, "")
        strat_box.pack_start(radio_primary, False, False, 0)
        strat_box.pack_start(radio_secondary, False, False, 0)
        strat_box.pack_start(radio_wipe, False, False, 0)
        strat_frame.add(strat_box)
        content.pack_start(strat_frame, False, False, 0)

        # ── Planned Changes ──
        changes_frame = Gtk.Frame(label="Planned Changes")
        changes_text = Gtk.TextView()
        changes_text.set_editable(False); changes_text.set_cursor_visible(False)
        changes_text.set_monospace(True)
        changes_scroll = Gtk.ScrolledWindow()
        changes_scroll.set_min_content_height(90)
        changes_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        changes_scroll.add(changes_text)
        changes_frame.add(changes_scroll)
        content.pack_start(changes_frame, False, False, 0)

        # ── After Layout ──
        after_frame = Gtk.Frame(label="Disk Layout After Changes")
        after_text = Gtk.TextView()
        after_text.set_editable(False); after_text.set_cursor_visible(False)
        after_text.set_monospace(True)
        after_scroll = Gtk.ScrolledWindow()
        after_scroll.set_min_content_height(100)
        after_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        after_scroll.add(after_text)
        after_frame.add(after_scroll)
        content.pack_start(after_frame, False, False, 0)

        # ── Buttons ──
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        confirm_btn = dialog.add_button("Confirm & Proceed", Gtk.ResponseType.OK)
        confirm_btn.get_style_context().add_class("suggested-action")

        # ── State tracking ──
        plan_state = {
            "strategy": "shrink_root",
            "target_disk": root_disk_path,
            "shrink_dev": None,
            "shrink_gb": 0,
        }

        # ── Update function ──
        def update_all(*_args):
            idx = disk_combo.get_active()
            if idx < 0 or idx >= len(disk_entries):
                return
            sel = disk_entries[idx]
            sel_path = sel["path"]
            is_root_disk = sel["is_root"]
            plan_state["target_disk"] = sel_path

            # Current layout
            layout_lines = get_disk_layout_text(sel_path)
            free_mib = get_disk_unallocated_mib(sel_path)
            free_gb = round(free_mib / 1024, 1)
            if free_gb > 0.01:
                layout_lines.append("")
                layout_lines.append(f"  Total unallocated space: {free_gb} GB")
            layout_text.get_buffer().set_text("\n".join(layout_lines))

            has_free = (free_gb >= (boot_gb + 1))

            change_lines = []
            after_lines = []

            if is_root_disk:
                # Root disk strategies: shrink btrfs or use free space
                radio_wipe.set_visible(False)
                fstype = self.fs_info["fstype"] if self.fs_info else ""
                can_shrink = (fstype == "btrfs")

                if has_free and can_shrink:
                    radio_primary.set_label(
                        f"Shrink root btrfs partition by {total_needed_gb} GB "
                        f"for Linux ({linux_gb} GB) + boot ({boot_gb} GB)")
                    radio_primary.set_visible(True); radio_primary.set_sensitive(True)
                    radio_secondary.set_label(
                        f"Use existing unallocated space ({free_gb} GB) – no shrink needed")
                    radio_secondary.set_visible(True); radio_secondary.set_sensitive(True)
                    strat_frame.set_visible(True)
                elif has_free:
                    radio_primary.set_label(
                        f"Use existing unallocated space ({free_gb} GB)")
                    radio_primary.set_visible(True); radio_primary.set_sensitive(True)
                    radio_secondary.set_visible(False)
                    strat_frame.set_visible(True)
                elif can_shrink:
                    radio_primary.set_label(
                        f"Shrink root btrfs partition by {total_needed_gb} GB")
                    radio_primary.set_visible(True); radio_primary.set_sensitive(True)
                    radio_secondary.set_visible(False)
                    strat_frame.set_visible(True)
                else:
                    radio_primary.set_label(
                        f"Cannot proceed: {fstype} is not shrinkable and no free space")
                    radio_primary.set_visible(True); radio_primary.set_sensitive(False)
                    radio_secondary.set_visible(False)
                    strat_frame.set_visible(True)

                # Determine strategy
                use_free = has_free and radio_secondary.get_visible() and radio_secondary.get_active()
                if not can_shrink and has_free:
                    use_free = True  # Only option

                if use_free:
                    plan_state["strategy"] = "use_free_root"
                    plan_state["shrink_dev"] = None
                    plan_state["shrink_gb"] = 0

                    root_size_gb = round(
                        (get_partition_info(root_dev)[0] or 0) / 1e9, 2)
                    change_lines.append("  1. Root partition is NOT modified")
                    change_lines.append(
                        f"  2. Create {boot_gb} GB FAT32 boot partition (LINUX_LIVE)")
                    change_lines.append(
                        f"  3. Remaining ~{round(free_gb - boot_gb, 1)} GB for Linux installation")
                    change_lines.append(
                        f"  4. Configure UEFI/GRUB boot entry for {distro_label}")

                    for p_line in get_disk_layout_text(sel_path):
                        if "[Unallocated]" not in p_line:
                            after_lines.append(p_line.rstrip() + "  (unchanged)")
                    remain_gb = round(free_gb - boot_gb, 1)
                    if remain_gb > 0:
                        after_lines.append(
                            f"  [Unallocated – Linux]  {remain_gb} GB  ← for Linux installer")
                    after_lines.append(
                        f"  LINUX_LIVE (FAT32)     {boot_gb} GB  ← {distro_label} live boot")
                else:
                    plan_state["strategy"] = "shrink_root"
                    plan_state["shrink_dev"] = root_dev
                    plan_state["shrink_gb"] = total_needed_gb

                    root_total, _ = get_partition_info(root_dev)
                    root_size_gb = round((root_total or 0) / 1e9, 2)
                    new_size_gb = round(root_size_gb - total_needed_gb, 2)

                    change_lines.append(
                        f"  1. Shrink root ({root_dev}) from "
                        f"{root_size_gb} GB to {new_size_gb} GB  (−{total_needed_gb} GB)")
                    change_lines.append(
                        f"  2. Create {boot_gb} GB FAT32 boot partition (LINUX_LIVE)")
                    change_lines.append(
                        f"  3. Leave {linux_gb} GB unallocated for Linux installation")
                    change_lines.append(
                        f"  4. Configure UEFI/GRUB boot entry for {distro_label}")

                    # Rebuild after layout
                    parts, _, _ = get_disk_partitions(sel_path)
                    _, root_part_num = self._resolve_disk_and_part(root_dev)
                    for p in parts:
                        if p["is_free"]:
                            continue
                        s_gb = round(p["size_mib"] / 1024, 2)
                        if p["num"] == root_part_num:
                            after_lines.append(
                                f"  Root ({root_dev})       {new_size_gb} GB  (shrunk)")
                            after_lines.append(
                                f"  [Unallocated – Linux]  {linux_gb} GB  ← for Linux installer")
                            after_lines.append(
                                f"  LINUX_LIVE (FAT32)     {boot_gb} GB  ← {distro_label} live boot")
                        else:
                            dev_p = _part_dev_path(sel_path, p["num"])
                            lbl = p["name"] or get_partition_fstype(dev_p) or "Partition"
                            after_lines.append(f"  {lbl:<22} {s_gb} GB")

            else:
                # ── Other disk ──
                # Find shrinkable partitions on target disk
                # btrfs can be shrunk live; ext4 can be shrunk if unmounted
                SHRINKABLE_FS = ("btrfs", "ext4", "ext3", "ext2", "ntfs")
                shrinkable = []
                parts, _, _ = get_disk_partitions(sel_path)
                for p in parts:
                    if p["is_free"] or p["num"] == 0:
                        continue
                    dev_p = _part_dev_path(sel_path, p["num"])
                    fs = get_partition_fstype(dev_p)
                    if fs in SHRINKABLE_FS:
                        total_b, free_b = get_partition_usage(dev_p)
                        if not total_b or not free_b:
                            # Partition might not be mounted — try fs-specific queries
                            if fs == "ntfs":
                                total_b, free_b = _ntfs_info(dev_p)
                            if not total_b or not free_b:
                                # Fallback: estimate from parted size (assume 50% free)
                                part_size_b = p["size_mib"] * 1024 * 1024
                                total_b = part_size_b
                                free_b = part_size_b // 2
                        if free_b > total_needed_gb * 1e9:
                            shrinkable.append({
                                "dev": dev_p,
                                "num": p["num"],
                                "fstype": fs,
                                "size_gb": round(p["size_mib"] / 1024, 2),
                                "free_gb": round(free_b / 1e9, 2),
                            })

                has_shrinkable = len(shrinkable) > 0

                # Find non-shrinkable partitions for explanation
                non_shrinkable_fs = []
                for p in parts:
                    if p["is_free"] or p["num"] == 0:
                        continue
                    dev_p = _part_dev_path(sel_path, p["num"])
                    fs = get_partition_fstype(dev_p)
                    if fs and fs not in SHRINKABLE_FS and fs not in ("vfat", "swap", ""):
                        non_shrinkable_fs.append({"dev": dev_p, "fstype": fs,
                            "size_gb": round(p["size_mib"] / 1024, 2)})

                if has_free:
                    radio_primary.set_label(
                        f"Use existing unallocated space ({free_gb} GB) on {sel['name']}")
                    radio_primary.set_visible(True); radio_primary.set_sensitive(True)
                    if not radio_primary.get_active() and not radio_secondary.get_active() \
                            and not radio_wipe.get_active():
                        radio_primary.set_active(True)
                else:
                    radio_primary.set_visible(False)
                    radio_primary.set_active(False)

                if has_shrinkable:
                    best = max(shrinkable, key=lambda s: s["free_gb"])
                    radio_secondary.set_label(
                        f"Shrink {best['dev']} ({best['fstype']}, {best['size_gb']} GB, "
                        f"{best['free_gb']} GB free) to make space")
                    radio_secondary.set_visible(True); radio_secondary.set_sensitive(True)
                    if not has_free and not radio_wipe.get_active():
                        radio_secondary.set_active(True)
                else:
                    radio_secondary.set_visible(False)
                    radio_secondary.set_active(False)

                # Always offer wipe & reformat for non-root disks if disk is large enough
                # Wipe only needs space for ESP (0.5 GB) + boot partition; the rest
                # is left unallocated for the Linux installer to use as it sees fit.
                wipe_min_gb = 0.5 + boot_gb + 1  # ESP + boot + at least 1 GB remaining
                disk_size_ok = (sel["size_gb"] >= wipe_min_gb)
                radio_wipe.set_label(
                    f"⚠ Wipe & reformat entire disk ({sel['size_gb']} GB) – "
                    f"ALL DATA ON {sel['name']} WILL BE DESTROYED")
                radio_wipe.set_visible(True)
                radio_wipe.set_sensitive(disk_size_ok)

                if not has_free and not has_shrinkable:
                    radio_primary.set_label(
                        f"No unallocated space or shrinkable partitions on {sel['name']}")
                    radio_primary.set_visible(True); radio_primary.set_sensitive(False)
                    if non_shrinkable_fs:
                        fs_list = ", ".join(
                            f"{x['dev']} ({x['fstype']})" for x in non_shrinkable_fs)
                        radio_secondary.set_label(
                            f"Cannot shrink {fs_list} – only btrfs/ext4/NTFS can be resized")
                        radio_secondary.set_visible(True); radio_secondary.set_sensitive(False)
                    if disk_size_ok and not radio_wipe.get_active():
                        radio_wipe.set_active(True)

                strat_frame.set_visible(True)

                # Determine strategy
                using_wipe = radio_wipe.get_visible() and radio_wipe.get_active()
                using_shrink = (has_shrinkable and
                    radio_secondary.get_visible() and radio_secondary.get_active())
                if has_shrinkable and not has_free and not using_wipe:
                    using_shrink = True

                if using_wipe:
                    plan_state["strategy"] = "wipe_disk"
                    plan_state["shrink_dev"] = None
                    plan_state["shrink_gb"] = 0

                    esp_gb = 0.5
                    usable_gb = round(sel["size_gb"] - esp_gb - boot_gb, 1)

                    change_lines.append("  ⚠ WARNING: This will ERASE ALL DATA on this disk!")
                    change_lines.append("")
                    change_lines.append("  1. Root partition is NOT modified (different disk)")
                    change_lines.append(
                        f"  2. Wipe {sel['name']} and create a new GPT partition table")
                    change_lines.append(
                        f"  3. Create 512 MB EFI System Partition (ESP)")
                    change_lines.append(
                        f"  4. Create {boot_gb} GB FAT32 boot partition (LINUX_LIVE)")
                    change_lines.append(
                        f"  5. Leave ~{usable_gb} GB unallocated for Linux installation")
                    change_lines.append(
                        f"  6. Configure UEFI/GRUB boot entry for {distro_label}")

                    after_lines.append(
                        f"  EFI System (ESP)       0.5 GB  ← UEFI boot files")
                    after_lines.append(
                        f"  LINUX_LIVE (FAT32)     {boot_gb} GB  ← {distro_label} live boot")
                    after_lines.append(
                        f"  [Unallocated – Linux]  ~{usable_gb} GB  ← for Linux installer")

                elif using_shrink:
                    best = max(shrinkable, key=lambda s: s["free_gb"])
                    plan_state["strategy"] = "other_disk_shrink"
                    plan_state["shrink_dev"] = best["dev"]
                    plan_state["shrink_gb"] = total_needed_gb

                    new_size_gb = round(best["size_gb"] - total_needed_gb, 2)
                    change_lines.append("  1. Root partition is NOT modified (different disk)")
                    change_lines.append(
                        f"  2. Shrink {best['dev']} from {best['size_gb']} GB to "
                        f"{new_size_gb} GB  (−{total_needed_gb} GB)")
                    change_lines.append(
                        f"  3. Create {boot_gb} GB FAT32 boot partition (LINUX_LIVE)")
                    change_lines.append(
                        f"  4. Leave {linux_gb} GB unallocated for Linux installation")
                    change_lines.append(
                        f"  5. Configure UEFI/GRUB boot entry for {distro_label}")

                    for p in parts:
                        if p["is_free"]:
                            continue
                        s_gb = round(p["size_mib"] / 1024, 2)
                        dev_p = _part_dev_path(sel_path, p["num"])
                        if dev_p == best["dev"]:
                            after_lines.append(
                                f"  {dev_p:<22} {new_size_gb} GB  (shrunk)")
                            after_lines.append(
                                f"  [Unallocated – Linux]  {linux_gb} GB  ← for Linux installer")
                            after_lines.append(
                                f"  LINUX_LIVE (FAT32)     {boot_gb} GB  ← {distro_label} live boot")
                        else:
                            lbl = p["name"] or get_partition_fstype(dev_p) or "Partition"
                            after_lines.append(f"  {lbl:<22} {s_gb} GB")

                elif has_free:
                    plan_state["strategy"] = "other_disk_free"
                    plan_state["shrink_dev"] = None
                    plan_state["shrink_gb"] = 0

                    change_lines.append("  1. Root partition is NOT modified (different disk)")
                    change_lines.append(
                        f"  2. Create {boot_gb} GB FAT32 boot partition (LINUX_LIVE) "
                        f"on {sel['name']}")
                    change_lines.append(
                        f"  3. Remaining unallocated space for Linux installation")
                    change_lines.append(
                        f"  4. Configure UEFI/GRUB boot entry for {distro_label}")

                    for p in parts:
                        if p["is_free"]:
                            continue
                        s_gb = round(p["size_mib"] / 1024, 2)
                        dev_p = _part_dev_path(sel_path, p["num"])
                        lbl = p["name"] or get_partition_fstype(dev_p) or "Partition"
                        after_lines.append(f"  {lbl:<22} {s_gb} GB  (unchanged)")
                    remain_gb = round(free_gb - boot_gb, 1)
                    if remain_gb > 0:
                        after_lines.append(
                            f"  [Unallocated – Linux]  {remain_gb} GB  ← for Linux installer")
                    after_lines.append(
                        f"  LINUX_LIVE (FAT32)     {boot_gb} GB  ← {distro_label} live boot")
                else:
                    plan_state["strategy"] = "blocked"
                    change_lines.append("  Cannot proceed with this disk.")
                    change_lines.append("")
                    if non_shrinkable_fs:
                        for nf in non_shrinkable_fs:
                            change_lines.append(
                                f"  {nf['dev']} is {nf['fstype']} "
                                f"({nf['size_gb']} GB) – cannot be shrunk live.")
                        change_lines.append("")
                        change_lines.append("  To use this disk, you would need to:")
                        change_lines.append("    – Back up your data from the drive")
                        change_lines.append(
                            "    – Shrink/delete the partition using GParted or parted")
                        change_lines.append("    – Re-run ULLI (it will detect the free space)")
                    else:
                        change_lines.append("  No unallocated space available on this disk.")

                    for p in parts:
                        if p["is_free"]:
                            continue
                        s_gb = round(p["size_mib"] / 1024, 2)
                        dev_p = _part_dev_path(sel_path, p["num"])
                        lbl = p["name"] or get_partition_fstype(dev_p) or "Partition"
                        after_lines.append(f"  {lbl:<22} {s_gb} GB  (unchanged)")
                    after_lines.append("")
                    after_lines.append("  (No changes – disk cannot be used as-is)")

            changes_text.get_buffer().set_text("\n".join(change_lines))
            after_text.get_buffer().set_text("\n".join(after_lines))

            # Disable confirm if blocked
            blocked = plan_state["strategy"] == "blocked"
            confirm_btn.set_sensitive(not blocked)

        # Wire events
        disk_combo.connect("changed", update_all)
        radio_primary.connect("toggled", update_all)
        radio_secondary.connect("toggled", update_all)
        radio_wipe.connect("toggled", update_all)

        # Initial update
        update_all()

        dialog.show_all()
        response = dialog.run()
        dialog.destroy()

        if response == Gtk.ResponseType.OK:
            return {
                "approved": True,
                "strategy": plan_state["strategy"],
                "target_disk": plan_state["target_disk"],
                "shrink_dev": plan_state["shrink_dev"],
                "shrink_gb": plan_state["shrink_gb"],
            }
        return None

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
        custom_mode = self.custom_radio.get_active()
        distro = DISTROS[distro_key]

        self.log(f"Root device : {device}")
        self.log(f"Filesystem  : {fstype}")
        self.log(f"Target size : {linux_gb} GB")
        self.log(f"Distro      : {distro['label']}")

        # ── 1b. Show disk plan – user must approve ─────────────────────────
        distro_label = distro["label"].split("(")[0].strip()
        plan_result = [None]
        plan_event = threading.Event()

        def show_plan_on_main():
            plan_result[0] = self._show_disk_plan(distro_label, linux_gb)
            plan_event.set()
            return False

        GLib.idle_add(show_plan_on_main)
        plan_event.wait()  # Block until dialog completes

        plan = plan_result[0]
        if not plan or not plan.get("approved"):
            self.log("Installation cancelled by user at disk plan review.")
            self.set_status("Ready")
            return

        strategy = plan["strategy"]
        target_disk = plan["target_disk"]
        shrink_dev = plan.get("shrink_dev")
        shrink_gb = plan.get("shrink_gb", 0)
        self.log(f"Disk plan approved. Strategy: {strategy}, Target: {target_disk}")

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

        # ── 3. execute strategy ────────────────────────────────────────────
        self._boot_part_dev = None  # set by strategy if applicable

        if strategy == "shrink_root":
            # Shrink root btrfs and create partitions on the same disk
            if fstype != "btrfs":
                self.log(f"Cannot shrink root: filesystem is {fstype}, not btrfs.", error=True)
                return
            ok = self._strategy_btrfs(device, linux_gb, iso_path, distro,
                                       distro_key, custom_mode)
        elif strategy == "use_free_root":
            # Use existing unallocated space on root disk
            ok = self._strategy_use_free(target_disk, linux_gb, iso_path,
                                          distro, distro_key, custom_mode)
        elif strategy == "other_disk_shrink":
            # Shrink a btrfs partition on another disk
            if not shrink_dev:
                self.log("No partition selected to shrink.", error=True)
                return
            ok = self._strategy_other_disk_shrink(
                target_disk, shrink_dev, shrink_gb, linux_gb,
                iso_path, distro, distro_key, custom_mode)
        elif strategy == "other_disk_free":
            # Use existing free space on another disk
            ok = self._strategy_use_free(target_disk, linux_gb, iso_path,
                                          distro, distro_key, custom_mode)
        elif strategy == "wipe_disk":
            # Wipe and reformat entire secondary disk
            ok = self._strategy_wipe_disk(target_disk, linux_gb, iso_path,
                                           distro, distro_key, custom_mode)
        else:
            self.log(f"Unknown strategy: {strategy}", error=True)
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
            if custom_mode and self.custom_iso_path:
                # Derive a label from the custom ISO filename
                iso_basename = os.path.basename(self.custom_iso_path)
                custom_label = os.path.splitext(iso_basename)[0]
                self._set_uefi_boot_entry(self._boot_part_dev, custom_label)
            else:
                self._set_uefi_boot_entry(self._boot_part_dev, distro["label"])
        if self.restart_check.get_active():
            self._do_restart()

        self.set_status("Installation complete!")
        self.log("=" * 52)
        self.log("All done! Review the log above for any warnings.")
        self.log("=" * 52)

    # ── ISO download ──────────────────────────────────────────────────────────
    def _download_iso(self, distro, dest):
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

    # ── shared strategy helpers ─────────────────────────────────────────────

    def _resize_partition_entry(self, disk_dev, part_num, part_start_mib, new_size_mib):
        """Shrink a partition table entry via sfdisk (with parted fallback).
        Returns actual new end MiB or None on failure."""
        new_part_end_mib = part_start_mib + new_size_mib
        new_size_sectors = new_size_mib * 2048
        self.log(f"Shrinking partition {part_num}: end → {new_part_end_mib} MiB "
                 f"({new_size_sectors} sectors)")
        self.set_status("Shrinking partition…")

        sfdisk_script = f"{part_num}: size={new_size_sectors}\n"
        result = subprocess.run(
            ["sfdisk", "--no-reread", "-N", str(part_num), disk_dev],
            input=sfdisk_script, capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.log(f"sfdisk resize failed: {result.stderr.strip()}", error=True)
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
                return None

        run(["partprobe", disk_dev])
        time.sleep(2)

        # Re-read actual end
        parts, _, _ = get_disk_partitions(disk_dev)
        for p in parts:
            if not p["is_free"] and p["num"] == part_num:
                self.log(f"Partition {part_num} now ends at {p['end_mib']} MiB.")
                return p["end_mib"]

        self.log("Cannot read partition table after resize.", error=True)
        return None

    def _create_boot_linux_parts(self, disk_path, boot_start, boot_end,
                                  linux_start, linux_end_str, is_gpt):
        """Create boot (LINUX_LIVE) and linux partitions via parted.
        linux_end_str can be "100%" or "NNNMiB".
        Returns (boot_dev, linux_dev) or None on failure."""
        self.log(f"Creating boot partition  {boot_start}–{boot_end} MiB …")
        self.set_status("Creating partitions…")

        if is_gpt:
            mkpart_boot  = ["mkpart", "LINUX_LIVE", "fat32",
                            f"{boot_start}MiB", f"{boot_end}MiB"]
            mkpart_linux = ["mkpart", "linux", "ext4",
                            f"{linux_start}MiB", linux_end_str]
        else:
            mkpart_boot  = ["mkpart", "primary", "fat32",
                            f"{boot_start}MiB", f"{boot_end}MiB"]
            mkpart_linux = ["mkpart", "primary", "ext4",
                            f"{linux_start}MiB", linux_end_str]

        cmd = ["parted", "-s", "--", disk_path] + mkpart_boot + mkpart_linux
        code, _, err = run(cmd)
        if code != 0:
            # Retry without fs-type hint
            self.log(f"parted mkpart: {err} – retrying without FS type hint", error=True)
            if is_gpt:
                mkpart_boot2  = ["mkpart", "LINUX_LIVE",
                                 f"{boot_start}MiB", f"{boot_end}MiB"]
                mkpart_linux2 = ["mkpart", "linux",
                                 f"{linux_start}MiB", linux_end_str]
            else:
                mkpart_boot2  = ["mkpart", "primary",
                                 f"{boot_start}MiB", f"{boot_end}MiB"]
                mkpart_linux2 = ["mkpart", "primary",
                                 f"{linux_start}MiB", linux_end_str]
            cmd2 = ["parted", "-s", "--", disk_path] + mkpart_boot2 + mkpart_linux2
            code, _, err2 = run(cmd2)
            if code != 0:
                self.log(f"Cannot create partitions: {err2}", error=True)
                return None

        time.sleep(2)
        run(["partprobe", disk_path])
        time.sleep(2)

        # Find newly created partitions by matching start positions
        parts, _, _ = get_disk_partitions(disk_path)
        boot_part_num = linux_part_num = None
        for p in parts:
            if p["is_free"] or p["num"] == 0:
                continue
            if abs(p["start_mib"] - boot_start) <= 2:
                boot_part_num = p["num"]
            elif abs(p["start_mib"] - linux_start) <= 2:
                linux_part_num = p["num"]

        if boot_part_num is None or linux_part_num is None:
            self.log(f"Cannot identify new partitions (boot={boot_part_num}, "
                     f"linux={linux_part_num}). Expected starts: "
                     f"{boot_start}, {linux_start} MiB", error=True)
            return None

        boot_dev = _part_dev_path(disk_path, boot_part_num)
        linux_dev = _part_dev_path(disk_path, linux_part_num)
        self.log(f"Boot partition  : {boot_dev}")
        self.log(f"Linux partition : {linux_dev}")
        return boot_dev, linux_dev

    def _format_and_populate_boot(self, boot_dev, iso_path, distro, distro_key):
        """Format boot_dev as FAT32, mount it, copy ISO contents. Returns True on success."""
        self.set_status("Formatting boot partition FAT32…")
        code, _, err = run(["mkfs.fat", "-F32", "-n", "LINUX_LIVE", boot_dev])
        if code != 0:
            self.log(f"mkfs.fat failed: {err}", error=True)
            return False

        mnt = "/mnt/linux_installer_boot"
        os.makedirs(mnt, exist_ok=True)
        run(["mount", boot_dev, mnt])
        try:
            ok = self._copy_iso_to_mount(iso_path, mnt, distro, distro_key)
        finally:
            run(["umount", mnt])
        return ok

    def _finalize_strategy(self, boot_dev, linux_dev, distro_label):
        """Set _boot_part_dev, log results, write instructions."""
        self.log(f"Boot partition ready at {boot_dev}.")
        self.log(f"Linux partition at {linux_dev} – "
                 "the installer will format this during installation.")
        self._boot_part_dev = boot_dev
        self._write_boot_instructions(
            boot_dev=boot_dev, linux_dev=linux_dev, distro_label=distro_label)

    # ── btrfs strategy ────────────────────────────────────────────────────────
    def _strategy_btrfs(self, device, linux_gb, iso_path, distro, distro_key, custom_mode):
        """Shrink root btrfs, resize partition entry, create boot+linux partitions."""
        self.log("")
        self.log("━━ Strategy: btrfs shrink + new partition ━━")

        total_shrink_gb = linux_gb + MIN_BOOT_GB

        # ── get btrfs usage ──
        self.set_status("Querying btrfs filesystem usage…")
        code, out, err = run(["btrfs", "filesystem", "usage", "-b", "/"])
        if code != 0:
            self.log(f"btrfs usage failed: {err}", error=True)
            return False

        dev_size = used = 0
        for line in out.splitlines():
            stripped = line.strip()
            if stripped.startswith("Device size:"):
                dev_size = int(stripped.split(":")[1].strip().split()[0])
            elif stripped.startswith("Used:"):
                used = int(stripped.split(":")[1].strip().split()[0])

        free_bytes = dev_size - used
        needed_bytes = total_shrink_gb * GiB
        safe_free = free_bytes - (10 * GiB)

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

        # ── find parent disk and partition, get layout ──
        disk_dev, part_num = self._resolve_disk_and_part(device)
        if not disk_dev:
            self.log("Cannot resolve parent disk for partition.", error=True)
            return False
        self.log(f"Disk: {disk_dev}  Partition: {part_num}")

        parts, disk_label, _ = get_disk_partitions(disk_dev)
        is_gpt = "gpt" in disk_label.lower()

        part_start_mib = part_end_mib = None
        next_part_start_mib = None
        for p in parts:
            if p["is_free"]:
                continue
            if p["num"] == part_num:
                part_start_mib = p["start_mib"]
                part_end_mib = p["end_mib"]
            elif p["num"] > part_num and next_part_start_mib is None:
                next_part_start_mib = p["start_mib"]

        if part_start_mib is None or part_end_mib is None:
            self.log("Cannot determine partition boundaries.", error=True)
            return False

        new_part_size_mib = part_end_mib - part_start_mib - total_shrink_gb * 1024
        if new_part_size_mib < 1:
            self.log("Calculated new partition size is too small!", error=True)
            return False

        # ── shrink the partition table entry ──
        actual_new_end = self._resize_partition_entry(
            disk_dev, part_num, part_start_mib, new_part_size_mib)
        if actual_new_end is None:
            self.log("You may need to grow the btrfs filesystem back with: "
                     "btrfs filesystem resize max /", error=True)
            return False

        # ── create boot + linux partitions in freed space ──
        boot_start = actual_new_end + 1
        boot_end = boot_start + MIN_BOOT_GB * 1024
        linux_start = boot_end + 1
        if next_part_start_mib is not None:
            linux_end_str = f"{next_part_start_mib - 1}MiB"
            self.log(f"Next partition starts at {next_part_start_mib} MiB, "
                     f"linux partition will end at {next_part_start_mib - 1} MiB")
        else:
            linux_end_str = "100%"

        result = self._create_boot_linux_parts(
            disk_dev, boot_start, boot_end, linux_start, linux_end_str, is_gpt)
        if result is None:
            return False
        boot_part_dev, linux_part_dev = result

        if not self._format_and_populate_boot(boot_part_dev, iso_path, distro, distro_key):
            return False

        self._finalize_strategy(boot_part_dev, linux_part_dev, distro["label"])
        return True

    # ── use-free-space strategy (root or other disk) ─────────────────────────
    def _strategy_use_free(self, disk_path, linux_gb, iso_path, distro,
                           distro_key, custom_mode):
        """Create partitions in existing unallocated space on disk_path."""
        self.log("")
        self.log("━━ Strategy: use existing unallocated space ━━")

        total_needed_gb = linux_gb + MIN_BOOT_GB

        parts, disk_label, _ = get_disk_partitions(disk_path)
        is_gpt = "gpt" in disk_label.lower()

        # Find largest free region that fits
        best_free = None
        for p in parts:
            if p["is_free"] and p["size_mib"] >= total_needed_gb * 1024:
                if best_free is None or p["size_mib"] > best_free["size_mib"]:
                    best_free = p

        if not best_free:
            self.log("No suitable unallocated region found on disk.", error=True)
            return False

        self.log(f"Using free region: {best_free['start_mib']}–{best_free['end_mib']} MiB "
                 f"({round(best_free['size_mib'] / 1024, 1)} GB)")

        boot_start = best_free["start_mib"] + 1
        boot_end = boot_start + MIN_BOOT_GB * 1024
        linux_start = boot_end + 1
        linux_end_str = f"{best_free['end_mib'] - 1}MiB"

        result = self._create_boot_linux_parts(
            disk_path, boot_start, boot_end, linux_start, linux_end_str, is_gpt)
        if result is None:
            return False
        boot_dev, linux_dev = result

        if not self._format_and_populate_boot(boot_dev, iso_path, distro, distro_key):
            return False

        self._finalize_strategy(boot_dev, linux_dev, distro["label"])
        return True

    # ── filesystem shrink helpers ───────────────────────────────────────────
    def _shrink_btrfs(self, dev, shrink_bytes):
        """Shrink a btrfs filesystem by shrink_bytes. Can be done live (mounted)."""
        code, mnt_out, _ = run(["findmnt", "-n", "-o", "TARGET", dev])
        if code != 0 or not mnt_out.strip():
            tmp_mnt = "/mnt/linux_installer_shrink_target"
            os.makedirs(tmp_mnt, exist_ok=True)
            code, _, err = run(["mount", dev, tmp_mnt])
            if code != 0:
                self.log(f"Cannot mount {dev}: {err}", error=True)
                return False
            mountpoint = tmp_mnt
            was_mounted = False
        else:
            mountpoint = mnt_out.strip()
            was_mounted = True

        try:
            self.set_status(f"Querying btrfs usage on {dev}…")
            code, out, err = run(["btrfs", "filesystem", "usage", "-b", mountpoint])
            if code != 0:
                self.log(f"btrfs usage failed: {err}", error=True)
                return False

            dev_size = 0
            for line in out.splitlines():
                stripped = line.strip()
                if stripped.startswith("Device size:"):
                    dev_size = int(stripped.split(":")[1].strip().split()[0])

            new_fs_size = dev_size - shrink_bytes
            self.log(f"Shrinking btrfs from {bytes_to_gb(dev_size)} GB "
                     f"to {bytes_to_gb(new_fs_size)} GB")
            self.set_status(f"Shrinking btrfs on {dev}…")
            code, _, err = run(["btrfs", "filesystem", "resize",
                                 str(new_fs_size), mountpoint])
            if code != 0:
                self.log(f"btrfs resize failed: {err}", error=True)
                return False
            self.log("btrfs filesystem shrunk successfully.")
            return True
        finally:
            if not was_mounted:
                run(["umount", mountpoint])

    def _shrink_ext(self, dev, shrink_bytes):
        """Shrink an ext2/3/4 filesystem by shrink_bytes. Must be unmounted first."""
        # Check if currently mounted
        code, mnt_out, _ = run(["findmnt", "-n", "-o", "TARGET", dev])
        if code == 0 and mnt_out.strip():
            self.log(f"{dev} is mounted at {mnt_out.strip()} — unmounting…")
            code, _, err = run(["umount", dev])
            if code != 0:
                self.log(f"Cannot unmount {dev}: {err}", error=True)
                self.log("ext4 must be unmounted before shrinking.", error=True)
                return False

        # Run e2fsck first (required before resize2fs)
        self.set_status(f"Checking filesystem on {dev}…")
        self.log(f"Running e2fsck on {dev}…")
        code, out, err = run(["e2fsck", "-f", "-y", dev])
        if code not in (0, 1):  # 1 = errors fixed
            self.log(f"e2fsck failed ({code}): {err}", error=True)
            return False

        # Get current size
        code, out, _ = run(["dumpe2fs", "-h", dev])
        block_size = block_count = 0
        for line in out.splitlines():
            if line.startswith("Block size:"):
                block_size = int(line.split(":")[1].strip())
            elif line.startswith("Block count:"):
                block_count = int(line.split(":")[1].strip())

        if block_size == 0 or block_count == 0:
            self.log("Cannot determine ext filesystem size.", error=True)
            return False

        current_size = block_size * block_count
        new_size = current_size - shrink_bytes
        new_blocks = new_size // block_size

        self.log(f"ext filesystem: {bytes_to_gb(current_size)} GB → "
                 f"{bytes_to_gb(new_size)} GB ({new_blocks} blocks)")

        # Resize
        self.set_status(f"Shrinking ext filesystem on {dev}…")
        code, _, err = run(["resize2fs", dev, f"{new_blocks}"])
        if code != 0:
            self.log(f"resize2fs failed: {err}", error=True)
            self.log("You may need to grow the filesystem back with: "
                     f"resize2fs {dev}", error=True)
            return False

        self.log("ext filesystem shrunk successfully.")
        return True

    def _shrink_ntfs(self, dev, shrink_bytes):
        """Shrink an NTFS filesystem by shrink_bytes using ntfsresize. Must be unmounted."""
        # Check if currently mounted
        code, mnt_out, _ = run(["findmnt", "-n", "-o", "TARGET", dev])
        if code == 0 and mnt_out.strip():
            self.log(f"{dev} is mounted at {mnt_out.strip()} — unmounting…")
            code, _, err = run(["umount", dev])
            if code != 0:
                self.log(f"Cannot unmount {dev}: {err}", error=True)
                self.log("NTFS must be unmounted before shrinking.", error=True)
                return False

        # Check ntfsresize is available
        if not shutil.which("ntfsresize"):
            self.log("ntfsresize not found. Install with: sudo apt install ntfs-3g",
                     error=True)
            return False

        # Query current NTFS size with --info
        self.set_status(f"Querying NTFS info on {dev}…")
        code, out, err = run(["ntfsresize", "--info", "--force", dev])
        if code != 0:
            self.log(f"ntfsresize --info failed: {err}", error=True)
            return False

        current_size = 0
        for line in out.splitlines():
            if "Current volume size" in line and "bytes" in line:
                current_size = _parse_bytes_value(line)
                break

        if current_size == 0:
            self.log("Cannot determine current NTFS volume size.", error=True)
            return False

        new_size = current_size - shrink_bytes
        if new_size < GiB:  # 1 GB minimum
            self.log(f"New NTFS size would be too small: {bytes_to_gb(new_size)} GB",
                     error=True)
            return False

        self.log(f"NTFS: {bytes_to_gb(current_size)} GB → {bytes_to_gb(new_size)} GB")

        # Do a dry run first
        self.set_status(f"Testing NTFS resize on {dev}…")
        code, out, err = run(["ntfsresize", "--no-action", "--size",
                               str(new_size), "--force", dev])
        if code != 0:
            self.log(f"ntfsresize dry run failed: {err}", error=True)
            return False
        self.log("Dry run OK, proceeding with actual resize…")

        # Actual resize (--force skips the interactive prompt)
        self.set_status(f"Shrinking NTFS on {dev}…")
        code, out, err = run(["ntfsresize", "--size", str(new_size), "--force", dev])
        if code != 0:
            self.log(f"ntfsresize failed: {err}", error=True)
            self.log("You may need to run chkdsk from Windows before retrying.",
                     error=True)
            return False

        self.log("NTFS filesystem shrunk successfully.")
        return True

    # ── other-disk-shrink strategy ───────────────────────────────────────────
    def _strategy_other_disk_shrink(self, disk_path, shrink_dev, shrink_gb,
                                     linux_gb, iso_path, distro, distro_key,
                                     custom_mode):
        """Shrink a partition on another disk and create boot+linux partitions."""
        self.log("")
        self.log("━━ Strategy: shrink partition on another disk ━━")
        self.log(f"Target disk: {disk_path}")
        self.log(f"Shrinking: {shrink_dev} by {shrink_gb} GB")

        # Verify and dispatch filesystem shrink
        fstype = get_partition_fstype(shrink_dev)
        if fstype not in ("btrfs", "ext4", "ext3", "ext2", "ntfs"):
            self.log(f"Cannot shrink {shrink_dev}: filesystem is {fstype}, "
                     f"only btrfs, ext4, and NTFS are supported.", error=True)
            return False

        needed_bytes = shrink_gb * GiB
        shrink_fn = {"btrfs": self._shrink_btrfs, "ntfs": self._shrink_ntfs}.get(
            fstype, self._shrink_ext)
        if not shrink_fn(shrink_dev, needed_bytes):
            return False

        # Get partition layout and find the shrunk partition
        _, part_num = self._resolve_disk_and_part(shrink_dev)
        if not part_num:
            self.log(f"Cannot resolve partition number for {shrink_dev}", error=True)
            return False

        parts, disk_label, _ = get_disk_partitions(disk_path)
        is_gpt = "gpt" in disk_label.lower()

        part_start_mib = part_end_mib = None
        next_part_start_mib = None
        for p in parts:
            if p["is_free"]:
                continue
            if p["num"] == part_num:
                part_start_mib = p["start_mib"]
                part_end_mib = p["end_mib"]
            elif p["num"] > part_num and next_part_start_mib is None:
                next_part_start_mib = p["start_mib"]

        if part_start_mib is None or part_end_mib is None:
            self.log("Cannot determine partition boundaries.", error=True)
            return False

        new_part_size_mib = part_end_mib - part_start_mib - shrink_gb * 1024

        actual_new_end = self._resize_partition_entry(
            disk_path, part_num, part_start_mib, new_part_size_mib)
        if actual_new_end is None:
            return False

        # Create boot + linux partitions in freed space
        boot_start = actual_new_end + 1
        boot_end = boot_start + MIN_BOOT_GB * 1024
        linux_start = boot_end + 1
        linux_end_str = f"{next_part_start_mib - 1}MiB" if next_part_start_mib else "100%"

        result = self._create_boot_linux_parts(
            disk_path, boot_start, boot_end, linux_start, linux_end_str, is_gpt)
        if result is None:
            return False
        boot_dev, linux_dev = result

        if not self._format_and_populate_boot(boot_dev, iso_path, distro, distro_key):
            return False

        self._finalize_strategy(boot_dev, linux_dev, distro["label"])
        return True

    # ── wipe-disk strategy (secondary drives only) ─────────────────────────
    def _strategy_wipe_disk(self, disk_path, linux_gb, iso_path, distro,
                            distro_key, custom_mode):
        """Wipe the entire secondary disk, create GPT, ESP, boot partition,
        and leave remaining space for the Linux installer."""
        self.log("")
        self.log("━━ Strategy: wipe & reformat entire disk ━━")
        self.log(f"Target disk: {disk_path}")

        boot_gb = MIN_BOOT_GB
        esp_mib = 512  # 512 MiB EFI System Partition

        # Safety: make sure this is NOT the root disk
        root_info = get_root_fs_info()
        if root_info:
            root_disk, _ = self._resolve_disk_and_part(root_info["device"])
            if root_disk and root_disk == disk_path:
                self.log("REFUSING to wipe the disk containing the running OS!",
                         error=True)
                return False

        # Unmount any partitions from this disk
        self.log("Unmounting any mounted partitions on target disk…")
        self.set_status("Unmounting target disk…")
        parts, _, _ = get_disk_partitions(disk_path)
        for p in parts:
            if p["is_free"] or p["num"] == 0:
                continue
            dev_p = _part_dev_path(disk_path, p["num"])

            # Deactivate swap if this partition is used as swap
            code, swap_out, _ = run(["swapon", "--show=NAME", "--noheadings"])
            if code == 0 and dev_p in swap_out:
                self.log(f"  Deactivating swap on {dev_p}")
                run(["swapoff", dev_p])

            # Unmount if mounted
            code, mnt_out, _ = run(["findmnt", "-n", "-o", "TARGET", dev_p])
            if code == 0 and mnt_out.strip():
                self.log(f"  Unmounting {dev_p} from {mnt_out.strip()}")
                code, _, err = run(["umount", "-f", dev_p])
                if code != 0:
                    # Try lazy unmount as last resort
                    self.log(f"  Force unmount failed, trying lazy unmount…")
                    code, _, err = run(["umount", "-l", dev_p])
                    if code != 0:
                        self.log(f"  Failed to unmount {dev_p}: {err}", error=True)
                        self.log("  Cannot proceed while partitions are in use.",
                                 error=True)
                        return False

        # Remove any device-mapper references (LVM, LUKS, etc.)
        for p in parts:
            if p["is_free"] or p["num"] == 0:
                continue
            dev_p = _part_dev_path(disk_path, p["num"])
            # Check for device-mapper holders
            dev_name = os.path.basename(dev_p)
            holders_dir = f"/sys/class/block/{dev_name}/holders"
            if os.path.isdir(holders_dir):
                for holder in os.listdir(holders_dir):
                    self.log(f"  Removing device-mapper mapping: {holder}")
                    run(["dmsetup", "remove", "--force", holder])

        # Tell the kernel to drop partition references
        self.log("Releasing kernel partition references…")
        run(["partprobe", disk_path])
        time.sleep(1)

        # ── Inhibit automounting BEFORE touching disk ──────────────────
        # Desktop environments (via udisks2) race to probe and mount new
        # partitions, which blocks mkfs with "Device or resource busy".
        # We must install inhibitors BEFORE creating any partitions.
        udev_rule_path = "/run/udev/rules.d/99-ulli-inhibit.rules"
        disk_basename = os.path.basename(disk_path)
        udev_rule_installed = False
        udisks_was_running = False

        try:
            os.makedirs("/run/udev/rules.d", exist_ok=True)
            with open(udev_rule_path, "w") as f:
                f.write(
                    f'SUBSYSTEM=="block", KERNEL=="{disk_basename}*", '
                    f'ENV{{UDISKS_IGNORE}}="1", ENV{{UDISKS_AUTO}}="0"\n')
            run(["udevadm", "control", "--reload-rules"])
            udev_rule_installed = True
            self.log("Automount inhibit udev rule installed.")
        except Exception as e:
            self.log(f"Note: could not set udev inhibit rule: {e}")

        # Stop udisks2 temporarily — this is the most reliable way to
        # prevent automounting since udev rules alone don't always work
        if shutil.which("systemctl"):
            code, _, _ = run(["systemctl", "is-active", "--quiet", "udisks2"])
            if code == 0:
                self.log("Stopping udisks2 service to prevent automounting…")
                run(["systemctl", "stop", "udisks2"])
                udisks_was_running = True

        try:
            # Wipe filesystem signatures so the kernel/parted don't consider
            # partitions "in use" based on residual superblocks
            if shutil.which("wipefs"):
                self.log(f"Wiping filesystem signatures on {disk_path}…")
                run(["wipefs", "--all", "--force", disk_path])
                for p in parts:
                    if p["is_free"] or p["num"] == 0:
                        continue
                    dev_p = _part_dev_path(disk_path, p["num"])
                    if os.path.exists(dev_p):
                        run(["wipefs", "--all", "--force", dev_p])

            time.sleep(1)

            # Wipe the partition table and create a fresh GPT
            self.log(f"Creating new GPT partition table on {disk_path}…")
            self.set_status("Creating new partition table…")
            code, _, err = run(["parted", "-s", disk_path, "mklabel", "gpt"])
            if code != 0:
                self.log(f"parted mklabel failed: {err}", error=True)
                # Fallback: use sgdisk --zap-all which is more forceful
                if shutil.which("sgdisk"):
                    self.log("Trying sgdisk fallback…")
                    code2, _, err2 = run(["sgdisk", "--zap-all", disk_path])
                    if code2 != 0:
                        self.log(f"sgdisk --zap-all also failed: {err2}", error=True)
                        return False
                    # sgdisk --zap-all leaves a blank disk; now create GPT
                    code3, _, err3 = run(["sgdisk", "-o", disk_path])
                    if code3 != 0:
                        self.log(f"sgdisk -o failed: {err3}", error=True)
                        return False
                    self.log("GPT created via sgdisk fallback.")
                else:
                    self.log("sgdisk not available for fallback. Install gdisk package.",
                             error=True)
                    return False

            run(["partprobe", disk_path])
            time.sleep(1)

            # Partition layout:
            #   1. ESP:        1 MiB – 513 MiB  (512 MiB, FAT32, esp flag)
            #   2. LINUX_LIVE: 513 MiB – (513 + boot_gb*1024) MiB  (FAT32, live ISO)
            #   3. Remaining:  unallocated for the Linux installer
            esp_start = 1        # MiB (1 MiB alignment)
            esp_end = esp_start + esp_mib
            boot_start = esp_end
            boot_end = boot_start + boot_gb * 1024

            self.log(f"Creating ESP partition: {esp_start}–{esp_end} MiB")
            self.log(f"Creating boot partition: {boot_start}–{boot_end} MiB")
            self.set_status("Creating partitions…")

            # Create ESP
            code, _, err = run(["parted", "-s", "--", disk_path,
                                "mkpart", "EFI", "fat32",
                                f"{esp_start}MiB", f"{esp_end}MiB",
                                "set", "1", "esp", "on"])
            if code != 0:
                self.log(f"Failed to create ESP: {err}", error=True)
                return False

            # Create boot partition
            code, _, err = run(["parted", "-s", "--", disk_path,
                                "mkpart", "LINUX_LIVE", "fat32",
                                f"{boot_start}MiB", f"{boot_end}MiB"])
            if code != 0:
                self.log(f"Failed to create boot partition: {err}", error=True)
                return False

            time.sleep(1)
            run(["partprobe", disk_path])
            if shutil.which("udevadm"):
                run(["udevadm", "settle", "--timeout=10"])
            time.sleep(1)

            # Identify the new partitions
            esp_dev = _part_dev_path(disk_path, 1)
            boot_dev = _part_dev_path(disk_path, 2)

            # Verify they exist
            for dev in (esp_dev, boot_dev):
                if not os.path.exists(dev):
                    time.sleep(3)
                    run(["partprobe", disk_path])
                    if shutil.which("udevadm"):
                        run(["udevadm", "settle", "--timeout=10"])
                    time.sleep(2)
                    if not os.path.exists(dev):
                        self.log(f"Partition device {dev} not found after creation.",
                                 error=True)
                        return False

            # Force-release anything holding these partitions
            for dev in (esp_dev, boot_dev):
                run(["umount", "-f", dev])
                if shutil.which("udisksctl"):
                    run(["udisksctl", "unmount", "-b", dev, "--no-user-interaction"])
                if shutil.which("wipefs"):
                    run(["wipefs", "--all", "--force", dev])
                # Kill any process using the device
                if shutil.which("fuser"):
                    run(["fuser", "-k", dev])
                # Check for device-mapper holders on this partition
                dev_name = os.path.basename(dev)
                holders_dir = f"/sys/class/block/{dev_name}/holders"
                if os.path.isdir(holders_dir):
                    for holder in os.listdir(holders_dir):
                        self.log(f"  Removing dm holder: {holder}")
                        run(["dmsetup", "remove", "--force", holder])

            time.sleep(1)

            # Wipe the first few MB of each new partition to clear any residual
            # signatures and release kernel probe locks before formatting
            for dev in (esp_dev, boot_dev):
                run(["dd", "if=/dev/zero", f"of={dev}",
                     "bs=1M", "count=2", "conv=notrunc", "status=none"])
            run(["partprobe", disk_path])
            if shutil.which("udevadm"):
                run(["udevadm", "settle", "--timeout=5"])
            time.sleep(1)

            # Format partitions
            for label, dev, name in [("ESP", esp_dev, "EFI System Partition"),
                                     ("LINUX_LIVE", boot_dev, "boot partition")]:
                self.log(f"Formatting {name} ({dev}) as FAT32…")
                self.set_status(f"Formatting {name}…")

                fmt_ok = False
                for attempt in range(4):
                    code, _, err = run(["mkfs.fat", "-F32", "-n", label, dev])
                    if code == 0:
                        fmt_ok = True
                        break
                    self.log(f"  Format attempt {attempt+1}/4 failed: {err}")
                    run(["umount", "-f", dev])
                    if shutil.which("fuser"):
                        run(["fuser", "-k", dev])
                    run(["dd", "if=/dev/zero", f"of={dev}",
                         "bs=1M", "count=1", "conv=notrunc", "status=none"])
                    time.sleep(2)

                if not fmt_ok:
                    self.log(f"mkfs.fat {name} failed: {err}", error=True)
                    return False

        finally:
            # Always remove the udev inhibit rule and restart udisks2
            if udev_rule_installed:
                try:
                    os.unlink(udev_rule_path)
                    run(["udevadm", "control", "--reload-rules"])
                    self.log("Automount inhibit rule removed.")
                except Exception:
                    pass
            if udisks_was_running:
                self.log("Restarting udisks2 service…")
                run(["systemctl", "start", "udisks2"])

        # Mount and copy ISO to boot partition
        mnt = "/mnt/linux_installer_boot"
        os.makedirs(mnt, exist_ok=True)
        run(["mount", boot_dev, mnt])
        try:
            ok = self._copy_iso_to_mount(iso_path, mnt, distro, distro_key)
        finally:
            run(["umount", mnt])

        if not ok:
            return False

        # Log the final layout
        self.log("")
        self.log(f"Disk {disk_path} wiped and reformatted successfully:")
        self.log(f"  Partition 1: {esp_dev}  – EFI System Partition (512 MB)")
        self.log(f"  Partition 2: {boot_dev} – LINUX_LIVE boot ({boot_gb} GB)")
        remaining_gb = round(
            (get_disk_partitions(disk_path)[2] / 1024) - (esp_mib / 1024) - boot_gb, 1)
        if remaining_gb > 0:
            self.log(f"  Remaining:   ~{remaining_gb} GB unallocated for Linux installer")

        self._boot_part_dev = boot_dev
        self._write_boot_instructions(
            boot_dev=boot_dev,
            linux_dev=f"{disk_path} (remaining unallocated space)",
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

                # Detect self-referential symlinks (e.g. ubuntu -> .) that would
                # cause rsync --copy-links to duplicate the entire tree.
                # We exclude those but still dereference other symlinks so that
                # paths like dists/stable -> noble are resolved on FAT32.
                exclude_args = []
                try:
                    for entry in os.listdir(iso_mnt):
                        full = os.path.join(iso_mnt, entry)
                        if os.path.islink(full):
                            target = os.path.realpath(full)
                            if os.path.realpath(iso_mnt) == target:
                                exclude_args += ["--exclude", f"/{entry}"]
                                self.log(f"Skipping self-referential symlink: {entry} -> .")
                except OSError:
                    pass

                code, _, err = run(
                    ["rsync", "-a", "--copy-links", "--info=progress2"]
                    + exclude_args +
                    [f"{iso_mnt}/", f"{mnt}/"],
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
                 "btrfs", "blkid", "update-grub",
                 "sfdisk", "resize2fs", "e2fsck", "lsblk",
                 "ntfsresize"]:
        if shutil.which(tool) is None:
            missing.append(tool)
    return missing


def ensure_root():
    """Re-launch the script as root via pkexec if not already elevated.

    pkexec provides a graphical (Polkit) password dialog, which fits
    naturally into the GTK workflow.  The current process is replaced
    seamlessly — from the user's perspective the app simply asks for
    their password and continues.

    Environment variables DISPLAY and XAUTHORITY (or WAYLAND_DISPLAY)
    are forwarded so the GTK window can still open under the user's
    desktop session.
    """
    if os.geteuid() == 0:
        return  # already root

    # Build the command: pkexec env <display‑vars> python3 this_script.py <args>
    # pkexec sanitises the environment, so we must explicitly pass
    # the display variables needed for the GUI to work.
    env_vars = []
    for var in ("DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY",
                "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"):
        val = os.environ.get(var)
        if val:
            env_vars.append(f"{var}={val}")

    cmd = ["pkexec", "env"] + env_vars + [sys.executable] + sys.argv

    try:
        os.execvp("pkexec", cmd)
    except Exception as e:
        # If pkexec is missing or the user cancels, fall back to sudo
        print(f"pkexec failed ({e}), trying sudo…")
        cmd_sudo = ["sudo", "--preserve-env=DISPLAY,XAUTHORITY,WAYLAND_DISPLAY,"
                    "XDG_RUNTIME_DIR,DBUS_SESSION_BUS_ADDRESS",
                    sys.executable] + sys.argv
        try:
            os.execvp("sudo", cmd_sudo)
        except Exception as e2:
            print(f"Could not obtain root privileges: {e2}", file=sys.stderr)
            print("Please re-run with:  sudo python3 " + " ".join(sys.argv))
            sys.exit(1)


if __name__ == "__main__":
    if "--check-deps" in sys.argv:
        m = check_deps()
        if m:
            print("Missing tools:", ", ".join(m))
            print("Install with:")
            print("  sudo apt install " +
                  "parted rsync dosfstools btrfs-progs grub-common "
                  "e2fsprogs fdisk util-linux ntfs-3g")
        else:
            print("All dependencies satisfied.")
        sys.exit(0)

    ensure_root()

    app = InstallerApp()
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    sys.exit(app.run(sys.argv))
