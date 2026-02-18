Install a bootable Linux partition to your hard drive from within Windows without a USB stick or manual BIOS configuration.

WARNING: This software is in alpha, and is not recommended for use on your main/critical PC.

You must download wli_v09010.bat and wli_v09010.ps1, right click on the .bat, and then run the program as administrator.

You may have to disable bitlocker/decrypt your hard drive to use this software.

You may have to disable Secure Boot in the BIOS depending on your computer.

To create a persistent installation after installing the live image, you must click on the install Linux Mint icon on the desktop from within the live partition Linux Mint OS. Once the partitioning screen comes up you must create a swap area (recommended at least 8 GB at the end of the free space), and an ext4 file system in the rest of the free space at /

Currently the installer only supports the installation of Linux Mint 22.3 Cinnamon. You may also use your own .iso files, but Debian and Fedora based distros don't work for now. Linux Mint Debian Edition is an exception.

wli sets Linux as the default boot entry automatically.

Released under GNU General Public License v3.0. You are free to do whatever you like with the source except distribute a closed source version.

Website: https://rltvty.net/installlinux.html
