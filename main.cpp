/*
 * Linux Mint 22.1 Partition Installer for Windows 11 UEFI Systems
 * C++ version for MSYS2/MinGW-w64
 * Must be run as Administrator
 * 
 * Compile with:
 * g++ -std=c++17 -o wli.exe wli.cpp -lwininet -lshell32 -lole32 -luuid -static
 */

#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
#include <filesystem>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <algorithm>
#include <thread>
#include <chrono>

#include <windows.h>
#include <wininet.h>
#include <shellapi.h>
#include <shlobj.h>

namespace fs = std::filesystem;

// Constants
const int MIN_PARTITION_SIZE_GB = 7;
const int MIN_LINUX_SIZE_GB = 20;
const int SECTOR_SIZE = 512;
const char* LINUX_MINT_URL = "https://mirrors.kernel.org/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso";

// Mirror URLs for fallback
const std::vector<std::string> MINT_MIRRORS = {
    "https://mirrors.kernel.org/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirror.csclub.uwaterloo.ca/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirrors.layeronline.com/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirror.arizona.edu/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso"
};

struct DriveInfo {
    char letter;
    std::string path;
    std::string label;
    std::string filesystem;
    double total_gb;
    double free_gb;
    bool is_system;
    int disk_number;
    int partition_number;
};

// Utility functions
bool isAdmin() {
    BOOL isAdmin = FALSE;
    PSID administratorsGroup = NULL;
    
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
    if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                 DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                                 &administratorsGroup)) {
        CheckTokenMembership(NULL, administratorsGroup, &isAdmin);
        FreeSid(administratorsGroup);
    }
    
    return isAdmin;
}

void runAsAdmin(const std::string& exePath) {
    ShellExecuteA(NULL, "runas", exePath.c_str(), NULL, NULL, SW_SHOWNORMAL);
}

void printHeader() {
    std::cout << std::string(60, '=') << std::endl;
    std::cout << "Linux Mint 22.1 Partition Installer - C++ Version" << std::endl;
    std::cout << "For Windows 11 UEFI Systems" << std::endl;
    std::cout << std::string(60, '=') << std::endl << std::endl;
}

std::string executeCommand(const std::string& command) {
    std::string result;
    char buffer[128];
    FILE* pipe = _popen(command.c_str(), "r");
    
    if (!pipe) {
        return "";
    }
    
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
        result += buffer;
    }
    
    _pclose(pipe);
    return result;
}

std::string executePowerShell(const std::string& command) {
    std::string fullCommand = "powershell -ExecutionPolicy Bypass -Command \"" + command + "\"";
    return executeCommand(fullCommand);
}

bool downloadWithProgress(const std::string& url, const std::string& destination) {
    std::cout << "\nDownloading from: " << url << std::endl;
    
    HINTERNET hInternet = InternetOpenA("MintInstaller/1.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!hInternet) {
        std::cerr << "Failed to initialize WinINet" << std::endl;
        return false;
    }
    
    HINTERNET hUrl = InternetOpenUrlA(hInternet, url.c_str(), NULL, 0, INTERNET_FLAG_RELOAD, 0);
    if (!hUrl) {
        InternetCloseHandle(hInternet);
        std::cerr << "Failed to open URL" << std::endl;
        return false;
    }
    
    // Get file size
    char sizeBuffer[32];
    DWORD sizeBufferLen = sizeof(sizeBuffer);
    DWORD index = 0;
    HttpQueryInfoA(hUrl, HTTP_QUERY_CONTENT_LENGTH, sizeBuffer, &sizeBufferLen, &index);
    
    long long totalSize = std::stoll(sizeBuffer);
    long long downloadedSize = 0;
    
    std::ofstream outFile(destination, std::ios::binary);
    if (!outFile) {
        InternetCloseHandle(hUrl);
        InternetCloseHandle(hInternet);
        std::cerr << "Failed to create output file" << std::endl;
        return false;
    }
    
    const int bufferSize = 8192;
    char buffer[bufferSize];
    DWORD bytesRead;
    
    while (InternetReadFile(hUrl, buffer, bufferSize, &bytesRead) && bytesRead > 0) {
        outFile.write(buffer, bytesRead);
        downloadedSize += bytesRead;
        
        // Progress bar
        double percent = (double)downloadedSize * 100.0 / totalSize;
        int barWidth = 40;
        int filled = (int)(barWidth * downloadedSize / totalSize);
        
        std::cout << "\r[";
        for (int i = 0; i < barWidth; i++) {
            if (i < filled) std::cout << "█";
            else std::cout << "-";
        }
        std::cout << "] " << std::fixed << std::setprecision(1) << percent << "% - ";
        std::cout << downloadedSize / (1024 * 1024) << "/" << totalSize / (1024 * 1024) << " MB";
        std::cout.flush();
    }
    
    std::cout << std::endl;
    
    outFile.close();
    InternetCloseHandle(hUrl);
    InternetCloseHandle(hInternet);
    
    return true;
}

bool downloadLinuxMint(const std::string& destination) {
    std::cout << "\nDownloading Linux Mint 22.1 ISO..." << std::endl;
    std::cout << "This will download approximately 2.9 GB" << std::endl;
    
    for (size_t i = 0; i < MINT_MIRRORS.size(); i++) {
        std::cout << "\nTrying mirror " << (i + 1) << "/" << MINT_MIRRORS.size() << std::endl;
        
        if (downloadWithProgress(MINT_MIRRORS[i], destination)) {
            std::cout << "\nDownload complete: " << destination << std::endl;
            return true;
        }
        
        if (i < MINT_MIRRORS.size() - 1) {
            std::cout << "Trying next mirror..." << std::endl;
        }
    }
    
    return false;
}

DriveInfo getCDriveInfo() {
    DriveInfo info;
    info.letter = 'C';
    info.path = "C:";
    info.is_system = true;
    
    // Get volume information
    char volumeName[MAX_PATH];
    char fileSystem[MAX_PATH];
    DWORD serialNumber;
    DWORD maxComponentLen;
    DWORD fileSystemFlags;
    
    if (GetVolumeInformationA("C:\\", volumeName, sizeof(volumeName),
                              &serialNumber, &maxComponentLen, &fileSystemFlags,
                              fileSystem, sizeof(fileSystem))) {
        info.label = volumeName;
        info.filesystem = fileSystem;
    }
    
    // Get disk space
    ULARGE_INTEGER freeBytesAvailable, totalBytes, totalFreeBytes;
    if (GetDiskFreeSpaceExA("C:\\", &freeBytesAvailable, &totalBytes, &totalFreeBytes)) {
        info.total_gb = totalBytes.QuadPart / (1024.0 * 1024.0 * 1024.0);
        info.free_gb = freeBytesAvailable.QuadPart / (1024.0 * 1024.0 * 1024.0);
    }
    
    // Get disk and partition numbers using PowerShell
    std::string diskCmd = "Get-Partition -DriveLetter C | Select-Object -ExpandProperty DiskNumber";
    std::string partCmd = "Get-Partition -DriveLetter C | Select-Object -ExpandProperty PartitionNumber";
    
    std::string diskResult = executePowerShell(diskCmd);
    std::string partResult = executePowerShell(partCmd);
    
    info.disk_number = diskResult.empty() ? 0 : std::stoi(diskResult);
    info.partition_number = partResult.empty() ? 2 : std::stoi(partResult);
    
    return info;
}

bool checkDiskSpace(DriveInfo& cInfo) {
    cInfo = getCDriveInfo();
    
    std::cout << "\nC: Drive Information:" << std::endl;
    std::cout << "  Total Size: " << std::fixed << std::setprecision(2) << cInfo.total_gb << " GB" << std::endl;
    std::cout << "  Free Space: " << cInfo.free_gb << " GB" << std::endl;
    std::cout << "  Disk Number: " << cInfo.disk_number << std::endl;
    std::cout << "  Partition Number: " << cInfo.partition_number << std::endl;
    
    double minRequired = MIN_PARTITION_SIZE_GB + MIN_LINUX_SIZE_GB + 10; // 10 GB buffer
    
    if (cInfo.free_gb < minRequired) {
        std::cerr << "\nError: Not enough free space on C: drive!" << std::endl;
        std::cerr << "Required: " << minRequired << " GB" << std::endl;
        std::cerr << "Available: " << cInfo.free_gb << " GB" << std::endl;
        return false;
    }
    
    return true;
}

std::pair<double, double> getLinuxSize() {
    double size;
    
    while (true) {
        std::cout << "\nHow much space do you want to allocate for Linux?" << std::endl;
        std::cout << "Minimum: " << MIN_LINUX_SIZE_GB << " GB" << std::endl;
        std::cout << "Recommended: 30-50 GB" << std::endl;
        std::cout << "Enter size in GB: ";
        
        if (std::cin >> size && size >= MIN_LINUX_SIZE_GB) {
            double totalNeeded = size + MIN_PARTITION_SIZE_GB;
            return {size, totalNeeded};
        }
        
        std::cerr << "Error: Size must be at least " << MIN_LINUX_SIZE_GB << " GB" << std::endl;
        std::cin.clear();
        std::cin.ignore(10000, '\n');
    }
}

bool shrinkCPartition(double sizeToShrinkGB) {
    std::cout << "\nShrinking C: partition by " << std::fixed << std::setprecision(2) 
              << sizeToShrinkGB << " GB..." << std::endl;
    
    int sizeMB = (int)(sizeToShrinkGB * 1024);
    
    // Create diskpart script
    std::string tempPath = std::getenv("TEMP") ? std::getenv("TEMP") : ".";
    std::string scriptPath = tempPath + "\\shrink_script.txt";
    
    std::ofstream script(scriptPath);
    script << "select volume c" << std::endl;
    script << "shrink desired=" << sizeMB << std::endl;
    script << "exit" << std::endl;
    script.close();
    
    // Execute diskpart
    std::string command = "diskpart /s \"" + scriptPath + "\"";
    std::string result = executeCommand(command);
    
    // Clean up
    std::remove(scriptPath.c_str());
    
    if (result.find("successfully") != std::string::npos) {
        std::cout << "C: partition shrunk successfully!" << std::endl;
        return true;
    }
    
    std::cerr << "Failed to shrink partition" << std::endl;
    return false;
}

std::string createNewPartition(int diskNumber, double sizeGB, const std::string& label = "LINUXMINT") {
    std::cout << "\nCreating new " << sizeGB << " GB partition..." << std::endl;
    
    int sizeMB = (int)(sizeGB * 1024);
    
    // Create diskpart script
    std::string tempPath = std::getenv("TEMP") ? std::getenv("TEMP") : ".";
    std::string scriptPath = tempPath + "\\create_script.txt";
    
    std::ofstream script(scriptPath);
    script << "select disk " << diskNumber << std::endl;
    script << "create partition primary size=" << sizeMB << std::endl;
    script << "format fs=fat32 label=" << label << " quick" << std::endl;
    script << "assign" << std::endl;
    script << "exit" << std::endl;
    script.close();
    
    // Execute diskpart
    std::string command = "diskpart /s \"" + scriptPath + "\"";
    std::string result = executeCommand(command);
    
    // Clean up
    std::remove(scriptPath.c_str());
    
    if (result.find("successfully") != std::string::npos) {
        // Wait for Windows to recognize the new partition
        std::this_thread::sleep_for(std::chrono::seconds(2));
        
        // Find the new drive letter
        for (char letter = 'D'; letter <= 'Z'; letter++) {
            std::string drive = std::string(1, letter) + ":";
            
            if (GetDriveTypeA((drive + "\\").c_str()) == DRIVE_FIXED) {
                char volumeName[MAX_PATH];
                if (GetVolumeInformationA((drive + "\\").c_str(), volumeName, sizeof(volumeName),
                                          NULL, NULL, NULL, NULL, 0)) {
                    if (std::string(volumeName) == label) {
                        std::cout << "New partition created and assigned to " << drive << std::endl;
                        return drive;
                    }
                }
            }
        }
    }
    
    std::cerr << "Failed to create partition" << std::endl;
    return "";
}

std::string mountISO(const std::string& isoPath) {
    std::cout << "\nMounting ISO..." << std::endl;
    
    std::string psCmd = "(Mount-DiskImage -ImagePath \\\"" + isoPath + 
                        "\\\" -PassThru | Get-Volume).DriveLetter";
    std::string result = executePowerShell(psCmd);
    
    // Remove whitespace
    result.erase(std::remove_if(result.begin(), result.end(), ::isspace), result.end());
    
    if (!result.empty()) {
        std::string mountedPath = result + ":";
        std::cout << "ISO mounted at " << mountedPath << std::endl;
        return mountedPath;
    }
    
    std::cerr << "Failed to mount ISO!" << std::endl;
    return "";
}

void unmountISO(const std::string& isoPath) {
    std::cout << "\nUnmounting ISO..." << std::endl;
    std::string psCmd = "Dismount-DiskImage -ImagePath \\\"" + isoPath + "\\\"";
    executePowerShell(psCmd);
}

bool copyFiles(const std::string& source, const std::string& target) {
    std::cout << "\nCopying Linux Mint files to " << target << "..." << std::endl;
    std::cout << "This may take 10-20 minutes..." << std::endl;
    
    // Use robocopy for reliable copying
    std::string robocopyCmd = "robocopy \"" + source + "\" \"" + target + 
                              "\" /E /R:3 /W:5 /NP /NFL /NDL /ETA";
    
    std::cout << "Starting file copy..." << std::endl;
    int result = std::system(robocopyCmd.c_str());
    
    // Robocopy exit codes: 0-7 are success codes
    if (result >= 8) {
        std::cerr << "Failed to copy files! Exit code: " << result << std::endl;
        return false;
    }
    
    std::cout << "Files copied successfully!" << std::endl;
    
    // Remove read-only attributes
    std::cout << "Removing read-only attributes..." << std::endl;
    std::string attribCmd = "attrib -R \"" + target + "\\*.*\" /S /D";
    std::system(attribCmd.c_str());
    
    return true;
}

void updateBootConfig(const std::string& targetDrive) {
    std::cout << "\nUpdating boot configuration files..." << std::endl;
    
    std::string grubDir = targetDrive + "\\boot\\grub";
    fs::create_directories(grubDir);
    
    std::string loopbackCfg = "# GRUB loopback configuration for Linux Mint\n"
                              "set timeout=5\n"
                              "set default=0\n"
                              "\n"
                              "menuentry \"Linux Mint 22.1\" {\n"
                              "    set root=(hd0,1)\n"
                              "    linux /casper/vmlinuz boot=casper quiet splash\n"
                              "    initrd /casper/initrd.lz\n"
                              "}\n"
                              "\n"
                              "menuentry \"Linux Mint 22.1 (Safe Mode)\" {\n"
                              "    set root=(hd0,1)\n"
                              "    linux /casper/vmlinuz boot=casper nomodeset quiet splash\n"
                              "    initrd /casper/initrd.lz\n"
                              "}\n"
                              "\n"
                              "menuentry \"Linux Mint 22.1 (Persistent - if configured)\" {\n"
                              "    set root=(hd0,1)\n"
                              "    linux /casper/vmlinuz boot=casper persistent quiet splash\n"
                              "    initrd /casper/initrd.lz\n"
                              "}\n";
    
    try {
        std::ofstream configFile(grubDir + "\\loopback.cfg");
        configFile << loopbackCfg;
        configFile.close();
        std::cout << "Boot configuration updated!" << std::endl;
    } catch (...) {
        std::cout << "Warning: Could not update boot configuration (files are read-only)" << std::endl;
        std::cout << "This is normal for ISO files - boot configuration will use defaults" << std::endl;
    }
}

void createHelperScripts(const std::string& targetDrive) {
    std::string grubScript = "#!/bin/bash\n"
                            "# GRUB configuration helper for Linux Mint\n"
                            "# Run this from Linux Mint live session if boot doesn't work\n"
                            "\n"
                            "echo \"Setting up GRUB for UEFI boot...\"\n"
                            "\n"
                            "# Mount the partition\n"
                            "sudo mkdir -p /mnt/mint\n"
                            "sudo mount " + targetDrive + " /mnt/mint\n"
                            "\n"
                            "# Install GRUB for UEFI\n"
                            "sudo apt-get update\n"
                            "sudo apt-get install -y grub-efi-amd64\n"
                            "\n"
                            "# Install GRUB to the partition\n"
                            "sudo grub-install --target=x86_64-efi --efi-directory=/mnt/mint --boot-directory=/mnt/mint/boot --removable --recheck\n"
                            "\n"
                            "# Create a basic GRUB configuration\n"
                            "cat > /mnt/mint/boot/grub/grub.cfg << 'EOF'\n"
                            "set timeout=5\n"
                            "set default=0\n"
                            "\n"
                            "menuentry \"Linux Mint 22.1 Live\" {\n"
                            "    set root=(hd0,1)\n"
                            "    linux /casper/vmlinuz boot=casper quiet splash\n"
                            "    initrd /casper/initrd.lz\n"
                            "}\n"
                            "\n"
                            "menuentry \"Linux Mint 22.1 (Compatibility Mode)\" {\n"
                            "    set root=(hd0,1)\n"
                            "    linux /casper/vmlinuz boot=casper nomodeset quiet splash\n"
                            "    initrd /casper/initrd.lz\n"
                            "}\n"
                            "EOF\n"
                            "\n"
                            "echo \"GRUB setup complete!\"\n"
                            "sudo umount /mnt/mint\n";
    
    std::ofstream scriptFile(targetDrive + "\\setup-grub.sh");
    scriptFile << grubScript;
    scriptFile.close();
}

bool setupUEFIBoot(const std::string& targetDrive, int diskNumber) {
    std::cout << "\nSetting up UEFI boot configuration..." << std::endl;
    
    // Check for EFI boot files
    std::vector<std::string> efiPaths = {
        targetDrive + "\\EFI\\BOOT\\BOOTx64.EFI",
        targetDrive + "\\EFI\\BOOT\\grubx64.efi"
    };
    
    bool efiFound = false;
    for (const auto& path : efiPaths) {
        if (fs::exists(path)) {
            efiFound = true;
            std::cout << "Found EFI boot file: " << fs::path(path).filename() << std::endl;
            break;
        }
    }
    
    if (!efiFound) {
        std::cout << "Warning: EFI boot file not found. Creating directory structure..." << std::endl;
        fs::create_directories(targetDrive + "\\EFI\\BOOT");
    }
    
    // Get partition number
    std::string psCmd = "Get-Partition -DriveLetter " + std::string(1, targetDrive[0]) + 
                        " | Select-Object -ExpandProperty PartitionNumber";
    std::string partitionNumber = executePowerShell(psCmd);
    partitionNumber.erase(std::remove_if(partitionNumber.begin(), partitionNumber.end(), ::isspace), 
                          partitionNumber.end());
    
    std::cout << "\nLinux Mint partition details:" << std::endl;
    std::cout << "  Drive Letter: " << targetDrive << std::endl;
    std::cout << "  Disk Number: " << diskNumber << std::endl;
    std::cout << "  Partition Number: " << partitionNumber << std::endl;
    
    // Create instructions file
    std::string instructions = "UEFI Boot Setup Instructions for Linux Mint\n"
                              "==========================================\n"
                              "\n"
                              "Your Linux Mint bootable partition has been created successfully!\n"
                              "\n"
                              "Partition Details:\n"
                              "- Drive: " + targetDrive + "\n"
                              "- Disk: " + std::to_string(diskNumber) + "\n"
                              "- Partition: " + partitionNumber + "\n"
                              "\n"
                              "To boot Linux Mint:\n"
                              "\n"
                              "1. Restart your computer\n"
                              "\n"
                              "2. Access UEFI/BIOS settings:\n"
                              "   - During startup, press the BIOS key (usually F2, F10, F12, DEL, or ESC)\n"
                              "   - The exact key depends on your motherboard manufacturer\n"
                              "\n"
                              "3. In UEFI settings:\n"
                              "   - Look for \"Boot\" or \"Boot Order\" section\n"
                              "   - Find the Linux Mint entry (may appear as \"UEFI: " + targetDrive + " LINUXMINT\")\n"
                              "   - Set it as the first boot priority\n"
                              "   - OR use the one-time boot menu (usually F12) to select it\n"
                              "\n"
                              "4. Important Settings:\n"
                              "   - Disable Secure Boot (if enabled)\n"
                              "   - Ensure UEFI mode is enabled (not Legacy/CSM)\n"
                              "   - Save changes and exit\n"
                              "\n"
                              "5. The system should now boot into Linux Mint Live environment\n"
                              "\n"
                              "Note: The Windows Boot Manager entry was NOT modified to prevent boot issues.\n"
                              "      Use the UEFI boot menu to select between Windows and Linux Mint.\n"
                              "\n"
                              "Troubleshooting:\n"
                              "- If you don't see the Linux Mint option, try disabling Fast Boot\n"
                              "- Some systems require you to manually add a boot entry pointing to:\n"
                              "  \\EFI\\BOOT\\BOOTx64.EFI on the LINUXMINT partition\n";
    
    // Save instructions to partition
    std::ofstream instructFile(targetDrive + "\\UEFI_BOOT_INSTRUCTIONS.txt");
    instructFile << instructions;
    instructFile.close();
    
    // Save to desktop
    char desktopPath[MAX_PATH];
    if (SHGetFolderPathA(NULL, CSIDL_DESKTOP, NULL, 0, desktopPath) == S_OK) {
        std::string desktopFile = std::string(desktopPath) + "\\Linux_Mint_Boot_Instructions.txt";
        std::ofstream desktopInstructFile(desktopFile);
        desktopInstructFile << instructions;
        desktopInstructFile.close();
    }
    
    return true;
}

bool checkUEFIMode() {
    std::string result = executePowerShell("$env:firmware_type");
    
    if (result.find("UEFI") != std::string::npos) {
        std::cout << "System is running in UEFI mode ✓" << std::endl;
        return true;
    }
    
    std::cout << "Warning: Cannot confirm UEFI mode. Proceeding anyway..." << std::endl;
    return true;
}

int main(int argc, char* argv[]) {
    // Check if running as admin
    if (!isAdmin()) {
        std::cout << "This program requires administrator privileges." << std::endl;
        std::cout << "Restarting as administrator..." << std::endl;
        runAsAdmin(argv[0]);
        return 0;
    }
    
    printHeader();
    
    try {
        // Check UEFI mode
        checkUEFIMode();
        
        // Step 1: Check disk space
        DriveInfo cInfo;
        if (!checkDiskSpace(cInfo)) {
            return 1;
        }
        
        // Step 2: Get desired Linux size from user
        auto [linuxSize, totalNeeded] = getLinuxSize();
        
        // Verify we have enough space
        if (cInfo.free_gb < totalNeeded + 10) {
            std::cerr << "\nError: Not enough free space!" << std::endl;
            std::cerr << "Need: " << (totalNeeded + 10) << " GB" << std::endl;
            std::cerr << "Have: " << cInfo.free_gb << " GB" << std::endl;
            return 1;
        }
        
        std::cout << "\nPlanned partition layout:" << std::endl;
        std::cout << "  Linux installation: " << linuxSize << " GB" << std::endl;
        std::cout << "  Linux Mint ISO: " << MIN_PARTITION_SIZE_GB << " GB" << std::endl;
        std::cout << "  Total to shrink from C: " << totalNeeded << " GB" << std::endl;
        
        std::cout << "\nProceed with partition changes? (yes/no): ";
        std::string confirm;
        std::cin >> confirm;
        
        if (confirm != "yes") {
            std::cout << "Operation cancelled." << std::endl;
            return 0;
        }
        
        // Step 3: Download Linux Mint ISO
        std::string tempPath = std::getenv("TEMP") ? std::getenv("TEMP") : ".";
        std::string isoPath = tempPath + "\\linuxmint-22.1.iso";
        
        if (fs::exists(isoPath)) {
            std::cout << "\nISO already exists at " << isoPath << ". Use existing? (y/n): ";
            char useExisting;
            std::cin >> useExisting;
            
            if (useExisting != 'y') {
                if (!downloadLinuxMint(isoPath)) {
                    std::cerr << "Failed to download Linux Mint ISO!" << std::endl;
                    return 1;
                }
            }
        } else {
            if (!downloadLinuxMint(isoPath)) {
                std::cerr << "Failed to download Linux Mint ISO!" << std::endl;
                return 1;
            }
        }
        
        // Step 4: Shrink C: partition
        if (!shrinkCPartition(totalNeeded)) {
            std::cerr << "Failed to shrink C: partition!" << std::endl;
            std::cerr << "You may need to:" << std::endl;
            std::cerr << "1. Run disk cleanup" << std::endl;
            std::cerr << "2. Disable hibernation (powercfg -h off)" << std::endl;
            std::cerr << "3. Temporarily disable system restore" << std::endl;
            std::cerr << "4. Reboot and try again" << std::endl;
            return 1;
        }
        
        // Step 5: Create new partition for Linux Mint ISO
        std::this_thread::sleep_for(std::chrono::seconds(5));
        
        std::string newDrive = createNewPartition(cInfo.disk_number, MIN_PARTITION_SIZE_GB);
        if (newDrive.empty()) {
            std::cerr << "Failed to create new partition!" << std::endl;
            return 1;
        }
        
        // Step 6: Mount ISO and copy files
        std::string sourcePath = mountISO(isoPath);
        if (sourcePath.empty()) {
            std::cerr << "Failed to mount ISO!" << std::endl;
            return 1;
        }
        
        // Copy files to new partition
        if (!copyFiles(sourcePath, newDrive)) {
            unmountISO(isoPath);
            std::cerr << "Failed to copy files!" << std::endl;
            return 1;
        }
        
        // Update boot configuration
        updateBootConfig(newDrive);
        
        // Create helper scripts
        createHelperScripts(newDrive);
        
        // Setup UEFI boot
        setupUEFIBoot(newDrive, cInfo.disk_number);
        
        // Unmount ISO
        unmountISO(isoPath);
        
        // Success message
        std::cout << "\n" << std::string(60, '=') << std::endl;
        std::cout << "Installation Complete!" << std::endl;
        std::cout << std::string(60, '=') << std::endl;
        std::cout << "\nLinux Mint has been installed to drive " << newDrive << std::endl;
        std::cout << "Reserved " << linuxSize << " GB for full Linux installation" << std::endl;
        
        std::cout << "\n*** IMPORTANT BOOT INSTRUCTIONS ***" << std::endl;
        std::cout << "\nThe Windows Boot Manager was NOT modified to prevent issues." << std::endl;
        std::cout << "To boot Linux Mint, you must use the UEFI boot menu:" << std::endl;
        
        std::cout << "\n1. Restart your computer" << std::endl;
        std::cout << "2. Press your BIOS/UEFI key during startup:" << std::endl;
        std::cout << "   - Common keys: F2, F10, F12, DEL, or ESC" << std::endl;
        std::cout << "   - Watch for the prompt on your screen" << std::endl;
        std::cout << "3. In the boot menu, select the Linux Mint entry" << std::endl;
        std::cout << "   - It may appear as 'UEFI: LINUXMINT' or similar" << std::endl;
        std::cout << "4. Make sure Secure Boot is disabled in UEFI settings" << std::endl;
        
        std::cout << "\nTo set Linux Mint as default boot option:" << std::endl;
        std::cout << "- Enter UEFI settings and change boot order" << std::endl;
        std::cout << "- Place Linux Mint entry before Windows Boot Manager" << std::endl;
        
        std::cout << "\nDetailed instructions saved to:" << std::endl;
        std::cout << "- " << newDrive << "\\UEFI_BOOT_INSTRUCTIONS.txt" << std::endl;
        std::cout << "- Desktop\\Linux_Mint_Boot_Instructions.txt" << std::endl;
        
        std::cout << "\nDuring Linux installation:" << std::endl;
        std::cout << "- You'll see " << linuxSize << " GB of unallocated space" << std::endl;
        std::cout << "- Install Linux Mint to that space" << std::endl;
        std::cout << "- The installer will set up dual boot properly" << std::endl;
        
        // Optionally delete the downloaded ISO
        std::cout << "\nDelete downloaded ISO file? (y/n): ";
        char deleteIso;
        std::cin >> deleteIso;
        
        if (deleteIso == 'y') {
            try {
                fs::remove(isoPath);
                std::cout << "ISO file deleted." << std::endl;
            } catch (...) {
                std::cout << "Could not delete ISO. File at: " << isoPath << std::endl;
            }
        }
        
    } catch (const std::exception& e) {
        std::cerr << "\nError: " << e.what() << std::endl;
        return 1;
    }
    
    std::cout << "\nPress Enter to exit...";
    std::cin.ignore();
    std::cin.get();
    
    return 0;
}
