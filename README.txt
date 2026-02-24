Install a bootable Linux partition to your hard drive without a USB stick or manual BIOS configuration.

WARNING: THIS SOFTWARE IS IN ALPHA AND IS NOT RECOMMENDED FOR USE ON YOUR MAIN/CRITICAL PC. THIS SOFTWARE IS PROVIDED AS-IS. THE AUTHOR ACCEPTS NO LIABILITY FOR DAMAGES OR DATA LOSS CAUSED BY THIS SOFTWARE. BACK UP YOUR DATA BEFORE USE. USE AT YOUR OWN RISK.

For Linux you must download ulli_v090143.py, then in the terminal run the following code: 

sudo python3 ulli_v090143.py

For Windows you must download ulli_v09014.bat and ulli_v09014.ps1, right click on the .bat, and then run the program as administrator.

You may have to disable bitlocker/decrypt your hard drive to use this software.

You may have to disable Secure Boot in the BIOS depending on your computer.

Currently the installer supports the installation of Linux Mint 22.3 Cinnamon, Ubuntu 24.04.4 LTS, Kubuntu 24.04.4 LTS, Debian Live 13.3.0 KDE, and Fedora 43 - KDE Plasma Desktop. You may also use your own .iso files, but Debian and Fedora based distros don't work for now. Linux Mint Debian Edition is an exception.

ulli attempts to set Linux as the default boot entry automatically, but this doesn't work on all systems. You may have to select Linux as the default boot option in the BIOS. The BIOS is accessible during startup by pressing F2, DEL, F10, ESC, F1, F12, or F11. Refer to your PC or motherboard's documentation for more information.

To create a persistent Kubuntu installation after creating the live partition, run the installer, and then when the partitioning option comes up choose replace partition and choose the free space created by the linux installer.

To create a persistent Linux Mint installation after installing the live image, you must click on the install Linux Mint icon on the desktop from within the live partition Linux Mint OS. Once the partitioning screen comes up you must create a swap area (equal to your RAM size. If disk space is limited, 8 GB is the minimum recommended.), and a btrfs file system in the rest of the free space at /. I recommend btrfs as opposed to ext4, because if you ever want to install another distro using this software, only btrfs supports resizing the mounted partition.

Under Linux Mint, Ubuntu, and Kubuntu, Windows can be accessed upon booting by selecting "Boot from next volume", however !WATCH OUT!, under Debian and Fedora, you must change your boot order in the BIOS to access Windows.

Released under GNU General Public License v3.0. You are free to do whatever you like with the source except distribute a closed source version.

Website: https://rltvty.net/installlinux.html
