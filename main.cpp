#include <iostream>
#include <fstream>
#include <string>
#include <windows.h>
#include <urlmon.h>
#pragma comment(lib, "urlmon.lib")

// Function to execute a system command
void executeCommand(const std::string& command) {
    system(command.c_str());
}

// Function to download a file
bool downloadFile(const std::string& url, const std::string& destination) {
    return URLDownloadToFileA(nullptr, url.c_str(), destination.c_str(), 0, nullptr) == S_OK;
}

// Function to write configuration content to a file
void writeConfigFile(const std::string& path, const std::string& content) {
    std::ofstream outFile(path);
    if (outFile.is_open()) {
        outFile << content;
        outFile.close();
    } else {
        std::cerr << "Unable to open file: " << path << std::endl;
    }
}

// Function to create a directory if it does not exist
void createDirectory(const std::string& path) {
    CreateDirectoryA(path.c_str(), nullptr);
}

// Embedded configuration file contents as string literals
const std::string cfgCin = R"(
#
#  Menu Entry 0       Boot An ISO file
#
#  ** Grub will boot this entry by default **
#
menuentry   'Boot An ISO file                                                   Hotkey=i'   --hotkey=i    --class isoboot   --class icon-isoboot  {
     set reviewpause=2
     echo GNU Grub is preparing to boot  Boot An ISO file
     set gfxpayload=1024x768
# start-grub2win-custom-code
#
#            This is sample code for booting from an iso file
#            via the Grub2Win g2wisoboot function
#
#            See the Grub2Win help file advanced topics section for more information
#
#            Note: There are many many ISO files available. They are all different.
#                  You must examine your particular ISO file with a utility like 7-Zip to
#                  obtain the proper kernel and initrd paths.
#                  You can then set the kernelpath and initrdpath variables below.
#                  The kernel and initrd files will not be found unless the correct paths are set.         
#
     clear
set isopath='/linuxmint-22.1-cinnamon-64bit.iso'
     set kernelpath='/casper/vmlinuz'                 # Example '/vmlinuz'
     set initrdpath='/casper/initrd.lz'                 # Example '/initrd.img'
     set bootparms='boot=casper iso-scan/filename='$isopath' reboot=cold nomodeset noprompt noeject ---'          # Example 'boot=/ iso-scan/filename='$isopath' noprompt noeject ---'
#
     g2wisoboot                                          # Run the g2wisoboot function
#
# end-grub2win-custom-code
     savelast 0 'Boot An ISO file'
}
)";

const std::string cfgXfce = R"(
#
#  Menu Entry 0       Boot An ISO file
#
#  ** Grub will boot this entry by default **
#
menuentry   'Boot An ISO file                                                   Hotkey=i'   --hotkey=i    --class isoboot   --class icon-isoboot  {
     set reviewpause=2
     echo GNU Grub is preparing to boot  Boot An ISO file
     set gfxpayload=1024x768
# start-grub2win-custom-code
#
#            This is sample code for booting from an iso file
#            via the Grub2Win g2wisoboot function
#
#            See the Grub2Win help file advanced topics section for more information
#
#            Note: There are many many ISO files available. They are all different.
#                  You must examine your particular ISO file with a utility like 7-Zip to
#                  obtain the proper kernel and initrd paths.
#                  You can then set the kernelpath and initrdpath variables below.
#                  The kernel and initrd files will not be found unless the correct paths are set.         
#
     clear
set isopath='/linuxmint-22-xfce-64bit.iso'
     set kernelpath='/casper/vmlinuz'                 # Example '/vmlinuz'
     set initrdpath='/casper/initrd.lz'                 # Example '/initrd.img'
     set bootparms='boot=casper iso-scan/filename='$isopath' reboot=cold nomodeset noprompt noeject ---'          # Example 'boot=/ iso-scan/filename='$isopath' noprompt noeject ---'
#
     g2wisoboot                                          # Run the g2wisoboot function
#
# end-grub2win-custom-code
     savelast 0 'Boot An ISO file'
}

)";

const std::string cfgUbu = R"(
#
#  Menu Entry 0       Boot An ISO file
#
#  ** Grub will boot this entry by default **
#
menuentry   'Boot An ISO file                                                   Hotkey=i'   --hotkey=i    --class isoboot   --class icon-isoboot  {
     set reviewpause=2
     echo GNU Grub is preparing to boot  Boot An ISO file
     set gfxpayload=1024x768
# start-grub2win-custom-code
#
#            This is sample code for booting from an iso file
#            via the Grub2Win g2wisoboot function
#
#            See the Grub2Win help file advanced topics section for more information
#
#            Note: There are many many ISO files available. They are all different.
#                  You must examine your particular ISO file with a utility like 7-Zip to
#                  obtain the proper kernel and initrd paths.
#                  You can then set the kernelpath and initrdpath variables below.
#                  The kernel and initrd files will not be found unless the correct paths are set.         
#
     clear
set isopath='/ubuntu-24.04.1-desktop-amd64.iso'
     set kernelpath='/casper/vmlinuz'                 # Example '/vmlinuz'
     set initrdpath='/casper/initrd'                 # Example '/initrd.img'
     set bootparms='boot=casper iso-scan/filename='$isopath' reboot=cold nomodeset noprompt noeject ---'          # Example 'boot=/ iso-scan/filename='$isopath' noprompt noeject ---'
#
     g2wisoboot                                          # Run the g2wisoboot function
#
# end-grub2win-custom-code
     savelast 0 'Boot An ISO file'
}

)";

const std::string grubCfg = R"(
#
#                 DO NOT EDIT THIS FILE!!
#
# It is automatically generated by C:\grub2\grub2win.exe
# using templates from             C:\grub2\winsource
# and settings from                C:\grub2\windata\customconfigs
# and user section code from       C:\grub2\userfiles\usersection.cfg
#
#       Created on Samstag  18 Mai 2024  at  20:37:48
#
# Generated by Grub2Win   Version 2.4.0.6   Build 1667   from directory  C:\grub2
# Gen Stamp                                 2024 - 0517 - 230410      Build 1667   ** Yesterday **
#
# The grub menu theme is - Basic
# The grub menu font  is - Unifont 16  -  Automatic
#
#  Grub2Win generated  6 menu entries
#  Includes GNU Grub version 2.12         The GNU Grub timeout is 30 seconds
#  
#
#  The current Windows display resolution is   1099x818
#  Grub resolution will be set at boot time to 1024x768,auto
#  The Grub default boot OS is menu entry 0  -  Boot An ISO file
#  The Grub locale language is ** Auto **   English   The locale code is - en
#


set default=0
set grub2win_chosen='0  -  Boot An ISO file'
set grub2win_version=2.4.0.6
set grub2win_langauto=yes
load_env grub2win_reboot
if [ ! $grub2win_reboot = no ] ; then set default=$grub2win_reboot ; set grub2win_reboot=no ; save_env grub2win_reboot ; fi
set timeout=30
set lang=en
set pager=1
set icondir=$prefix/themes/icons
set locale_dir=$prefix/locale
if [ -z $grub2win_funcstatus ] ; then source $prefix/g2bootmgr/gnugrub.functions.cfg ; fi 
g2wbits 
set grub2win_custmode=EFI
set grub2win_lastbooted=no
set grub2win_efilevel=159
set grub2win_efiuuid=A699-2EF0
set gfxmode=1024x768,auto
set theme=$prefix/themes/custom.config
if [ $grub2win_bootmode = EFI ] ; then set theme=$theme.$grub2win_efibits.efi.txt ; else set theme=$theme.$grub2win_procbits.bios.txt ; fi
export theme
export icondir
set gfxpayload=text
insmod png
insmod all_video
source $prefix/winsource/template.gfxfonts.cfg
load_env grub2win_gfxmode
if [ ! -z $grub2win_gfxmode ] ; then set gfxmode=$grub2win_gfxmode ; fi
insmod gfxterm
terminal_output gfxterm
insmod gfxmenu


# start-grub2win-auto-menu-section  ***************************************************
#

#
#  Menu Entry For Custom Code 0       Boot An ISO file
#
#  ** Grub will boot this entry by default **
#
#   Comment 'Boot An ISO file                                                   Hotkey=i'   --hotkey=i    --class isoboot   --class icon-isoboot
#
     source $prefix/windata/customconfigs/BootAnISOfile.cfg
#

#
#  Menu Entry 1       Windows EFI Boot Manager
#
menuentry   'Windows EFI Boot Manager                                           Hotkey=w'   --hotkey=w    --class windows   --class icon-windows  {
     set reviewpause=5
     set pager=0
     if [ $grub_platform = efi ]; then
         set efibootmgr=/efi/Microsoft/Boot/bootmgfw.efi
         getpartition  file  $efibootmgr  root
         if [ $? = 0 ] ; then
         echo Grub is now loading the Windows EFI Boot Manager
             echo Boot disk address is    $root
             echo The boot mode is        Windows EFI
             chainloader $efibootmgr
         fi
     else
         if [ -f (hd0,1)/ntldr ]; then
             set bootcontrol="XP NTLDR"
             set root=(hd0,1)
             set bootmodule=microsoft.ntldr.xp.bios
	     if [ ! -f ($root)/$bootmodule ] ; then set bootmodule=ntldr ; fi
         else
             set biosbootmgr=/bootmgr
             getpartition  file  $biosbootmgr  root
             set bootcontrol=BCD
             set bootmodule=microsoft.bootmgr.bios
             if [ ! -f ($root)/$bootmodule ] ; then set bootmodule=bootmgr ; fi
         fi
         echo
         echo The Windows BIOS boot manager is at address ($root)
         echo
         echo The Windows boot control type is $bootcontrol
         echo
         ntldr /$bootmodule
     fi
     g2wsleep
     savelast 1 'Windows EFI Boot Manager'
}


#
#  Menu Entry 2       Boot Information and Utilities
#
menuentry   'Boot Information and Utilities                                     Hotkey=b'   --hotkey=b    --class bootinfo   --class icon-bootinfo  {
     unset reviewpause
     g2wbootinfo
}


#
#  Menu Entry 3       Shutdown the system
#
menuentry   'Shutdown the system                                                Hotkey=s'   --hotkey=s    --class shutdown   --class icon-shutdown  {
     unset reviewpause
     g2wutil halt
}


#
#  Menu Entry 4       Reboot your system
#
menuentry   'Reboot your system                                                 Hotkey=r'   --hotkey=r    --class reboot   --class icon-reboot  {
     unset reviewpause
     g2wutil reboot
}


#
#  Menu Entry 5       Boot to your EFI firmware
#
menuentry   'Boot to your EFI firmware                                          Hotkey=f'   --hotkey=f    --class bootfirmware   --class icon-bootfirmware  {
     unset reviewpause
     g2wutil fwsetup
}


#
# end-grub2win-auto-menu-section    ***************************************************
)";

// Main function for installation steps
int main() {
    // Step 1: Disable test signing mode
    executeCommand("bcdedit -set TESTSIGNING OFF");

    // Step 2: Download grub2win.zip
    std::cout << "Downloading Grub2Win..." << std::endl;
    executeCommand("powershell -Command \"Start-BitsTransfer -Source 'https://sourceforge.net/projects/grub2win/files/grub2win.zip/download' -Destination 'C:/grub2win.zip' \"");


    // Step 3: Extract the ZIP file
    std::cout << "Extracting Grub2Win..." << std::endl;
    executeCommand("powershell -Command \"Expand-Archive -Path 'C:\\grub2win.zip' -DestinationPath 'C:\\' -Force\"");

    // Step 4: Run the Grub2Win installer
    std::cout << "Running Grub2Win installer..." << std::endl;
    executeCommand("start C:\\G2WInstall.exe");

    // Wait for user confirmation
    std::cout << "Press any key after Grub2Win installation is complete." << std::endl;
    std::cin.get();

    // Step 5: Write grub.cfg file
    writeConfigFile("C:\\grub2\\grub.cfg", grubCfg);

    // Step 6: Create custom configs directory
    createDirectory("C:\\grub2\\windata\\customconfigs");

    // Step 7: OS Selection Menu
    std::cout << "Select your OS:" << std::endl;
    std::cout << "1 - Linux Mint 22.1 Cinnamon" << std::endl;
    std::cout << "2 - Linux Mint 22 XFCE" << std::endl;
    std::cout << "3 - Ubuntu 24.04.1 LTS" << std::endl;

    int choice;
    std::cout << "Type a number and press ENTER: ";
    std::cin >> choice;

    std::string isoUrl, cfgContent;

    switch (choice) {
        case 1:
            executeCommand("powershell -Command \"Start-BitsTransfer -Source 'https://mirrors.layeronline.com/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso' -Destination 'C:/linuxmint-22.1-cinnamon-64bit.iso' \"");
            cfgContent = cfgCin;
            break;
        case 2:
            executeCommand("powershell -Command \"Start-BitsTransfer -Source 'https://mirrors.layeronline.com/linuxmint/stable/22/linuxmint-22-xfce-64bit.iso' -Destination 'C:/linuxmint-22-xfce-64bit.iso' \"");
            cfgContent = cfgXfce;
            break;
        case 3:
            executeCommand("powershell -Command \"Start-BitsTransfer -Source 'https://mirrors.edge.kernel.org/ubuntu-releases/24.04.1/ubuntu-24.04.1-desktop-amd64.iso' -Destination 'C:/ubuntu-24.04.1-desktop-amd64.iso' \"");
            cfgContent = cfgUbu;
            break;
        default:
            std::cerr << "Invalid choice." << std::endl;
            return 1;
    }

    // Step 8: Write the selected configuration content to the file
    writeConfigFile("C:\\grub2\\windata\\customconfigs\\BootAnISOfile.cfg", cfgContent);

    // Step 9: Download the selected ISO
    

    // Step 10: Reboot the system
    std::cout << "Rebooting the system..." << std::endl;
    executeCommand("shutdown /r");

    return 0;
}
