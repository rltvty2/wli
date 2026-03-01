# ULLI:    USB-less Linux Installer

**Donations/tips:** [https://ko-fi.com/rltvty](https://ko-fi.com/rltvty)

**Website:** [https://rltvty.net/installlinux.html](https://rltvty.net/installlinux.html)

Install a bootable Linux partition to your hard drive without a USB stick or manual BIOS configuration.

> **⚠️ WARNING:** THIS SOFTWARE IS IN ALPHA AND IS NOT RECOMMENDED FOR USE ON YOUR MAIN/CRITICAL PC. THIS SOFTWARE IS PROVIDED AS-IS. THE AUTHOR ACCEPTS NO LIABILITY FOR DAMAGES OR DATA LOSS CAUSED BY THIS SOFTWARE. BACK UP YOUR DATA BEFORE USE. USE AT YOUR OWN RISK.

---

Acknowledgement: AI (mostly Claude) was used in the development of this software. That being said I always test before releasing code.

## Running under Linux

Download `ulli-linux.py`, right click on `ulli-linux.py`, click properties, and then, under the permissions tab check "Allow this file to run as a program". Then double click on the `.py` and click "Run in Terminal".

Alternatively just run this code in your terminal, in the same folder you downloaded to:

```
sudo python3 ulli-linux.py
```

## Running under Windows

Download `ulli-windows.zip`, extract all files, right click on `run-ulli-windows.bat`, and then run the program as administrator.

Alternatively you can turn off smart app control under windows security, and then simply double click on `run-ulli-windows.bat` to run the program.

---

## Important Notes

- You may have to disable bitlocker/decrypt your hard drive to use this software.

- You may have to disable Secure Boot in the BIOS depending on your computer.

- Currently the installer supports the installation of **Linux Mint 22.3 Cinnamon**, **Ubuntu 24.04.4 LTS**, **Kubuntu 24.04.4 LTS**, **Debian Live 13.3.0 KDE**, and **Fedora 43 - KDE Plasma Desktop**. You may also use your own `.iso` files, but Debian and Fedora based distros don't work for now. Linux Mint Debian Edition is an exception.

- ulli attempts to set Linux as the default boot entry automatically, but this doesn't work on all systems. You may have to select Linux as the default boot option in the BIOS. The BIOS is accessible during startup by pressing F2, DEL, F10, ESC, F1, F12, or F11. Refer to your PC or motherboard's documentation for more information.

---

## Post-Installation

### Kubuntu

To create a persistent Kubuntu installation after creating the live partition, run the installer, and then when the partitioning option comes up choose replace partition and choose the free space created by the linux installer.

### Linux Mint

To create a persistent Linux Mint installation after installing the live image, you must click on the install Linux Mint icon on the desktop from within the live partition Linux Mint OS. Once the partitioning screen comes up you must create a swap area (equal to your RAM size. If disk space is limited, 8 GB is the minimum recommended.), and a btrfs file system in the rest of the free space at `/`. I recommend btrfs as opposed to ext4, because if you ever want to install another distro using this software, only btrfs supports resizing the mounted partition.

---

## Accessing Windows

Under Linux Mint, Ubuntu, and Kubuntu, Windows can be accessed upon booting by selecting "Boot from next volume", however **⚠️ WATCH OUT** — under Debian and Fedora, you must change your boot order in the BIOS to access Windows.

---

## License

Released under **GNU General Public License v3.0**. You are free to do whatever you like with the source except distribute a closed source version.
