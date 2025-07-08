Install Linux from within Windows without a USB stick

WARNING: This software is in alpha, and is not recommended for use on your main/critical PC.

You must download wli_v09005.bat and wli_v09005.ps1, right click on the .bat, and then run the program as administrator.

Windows defender will try to stop you from running the program. Click run anyways.

You have to disable bitlocker/decrypt your hard drive to use this software.

After the installation is complete, you will have to give the new boot entry priority in your BIOS settings.

You may have to disable Secure Boot in the BIOS depending on your computer.

To create a persistent Kubuntu installation after creating the live partition, run the installer, and then when the partitioning option comes up choose replace partition and choose the free space created by the windows linux installer.

For Linux Mint the process is a bit more involved. You must click on the install Linux Mint icon on the desktop from within the live partition Linux Mint OS. Once the partitioning screen comes up you must create a swap area (recommended 8 GB at the end of the free space), and an ext4 file system in the rest of the free space at /

Currently the installer supports installation of Kubuntu 25.04 and Linux Mint 22.1 Cinnamon.

Released under GNU General Public License v3.0. You are free to do whatever you like with the source except distribute a closed source version.

Website: https://rltvty.net/installlinux.html
