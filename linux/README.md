# ULLI USB-less Linux Installer

A GUI tool to install a second Linux distro alongside your existing one —
**no USB drive required**.

Supports:
| Distro | Desktop |
|---|---|
| Linux Mint 22.3 "Zena" | Cinnamon |
| Ubuntu 24.04.4 LTS | GNOME |
| Kubuntu 24.04.4 LTS | KDE Plasma |
| Debian Live 13.3.0 | KDE |
| Fedora 43 | KDE Plasma |

---

### btrfs  →  Shrink + new partition
If your root filesystem is **btrfs**, the installer:
1. Shrinks the btrfs filesystem online (no unmount needed).
2. Creates two new partitions in the freed space:
   - A **7 GB FAT32** boot partition containing the live ISO files.
   - An **unformatted** partition for the target distro's installer to use.
3. Sets a GRUB entry for the new partition.
4. On reboot you boot the live environment from the FAT32 partition and
   run the distro's installer, which will automatically find the
   unformatted partition.

---

## Requirements

```bash
# Debian / Ubuntu / Mint
sudo apt install python3 python3-gi gir1.2-gtk-3.0 gir1.2-vte-2.91 \
                 parted btrfs-progs dosfstools e2fsprogs \
                 squashfs-tools rsync grub-common p7zip-full

# Fedora
sudo dnf install python3 python3-gobject gtk3 \
                 parted btrfs-progs dosfstools e2fsprogs \
                 squashfs-tools rsync grub2-tools p7zip
```

---

## Running

```bash
# The installer needs root to create partitions / mount filesystems
sudo python3 ulli_v090144.py
```

---

## Command-line flags

| Flag | Description |
|---|---|
| `--check-deps` | Check for required tools without launching the GUI |

---

## Notes

- The ISO is cached in `~/.cache/linux-installer/` so a re-run won't
  re-download it unless the checksum fails.
- SHA-256 checksums are verified for all official ISOs.
- The **Delete ISO after installation** checkbox removes the cache file
  once copying is complete.
- Fedora's hybrid ISO is extracted with `7z`; all boot config `LABEL=`
  references are patched to match the `LINUX_LIVE` FAT32 volume label.
