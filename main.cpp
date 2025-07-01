/*
 * Linux Mint 22.1 Partition Installer for Windows 11 UEFI Systems
 * GUI Version using Win32 API
 * Must be run as Administrator
 * 
 * Compile with:
 * g++ -std=c++17 -o wli.exe main.cpp -lwininet -lshell32 -lole32 -luuid -lcomctl32 -lgdi32 -mwindows -static
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
#include <atomic>
#include <mutex>

#include <windows.h>
#include <wininet.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commctrl.h>
#include <richedit.h>

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

// Window controls
enum {
    ID_STATIC_HEADER = 1000,
    ID_STATIC_STATUS,
    ID_STATIC_DISK_INFO,
    ID_STATIC_SIZE_LABEL,
    ID_EDIT_SIZE,
    ID_SPIN_SIZE,
    ID_BUTTON_START,
    ID_BUTTON_EXIT,
    ID_PROGRESS_BAR,
    ID_RICHEDIT_LOG,
    ID_CHECK_DELETE_ISO,
    ID_STATIC_GROUP_DISK,
    ID_STATIC_GROUP_SIZE,
    ID_STATIC_GROUP_LOG
};

// Global variables
HWND g_hWnd = NULL;
HWND g_hStatusText = NULL;
HWND g_hDiskInfo = NULL;
HWND g_hSizeEdit = NULL;
HWND g_hStartButton = NULL;
HWND g_hExitButton = NULL;
HWND g_hProgressBar = NULL;
HWND g_hLogEdit = NULL;
HWND g_hDeleteIsoCheck = NULL;
HFONT g_hHeaderFont = NULL;
HFONT g_hNormalFont = NULL;
HICON g_hIcon = NULL;

std::atomic<bool> g_isRunning(false);
std::mutex g_logMutex;
std::string g_isoPath;

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

DriveInfo g_cDriveInfo;

// Forward declarations
LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam);
void InitializeControls(HWND hwnd);
void UpdateDiskInfo();
void LogMessage(const std::string& message, bool isError = false);
void SetStatus(const std::string& status);
void EnableControls(bool enable);
DWORD WINAPI InstallationThread(LPVOID lpParam);

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
    SHELLEXECUTEINFOA sei = {0};
    sei.cbSize = sizeof(sei);
    sei.lpVerb = "runas";
    sei.lpFile = exePath.c_str();
    sei.hwnd = NULL;
    sei.nShow = SW_NORMAL;
    
    if (!ShellExecuteExA(&sei)) {
        DWORD error = GetLastError();
        if (error == ERROR_CANCELLED) {
            // User cancelled the elevation prompt
            MessageBoxA(NULL, "Administrator privileges are required to run this program.", 
                       "Permission Denied", MB_OK | MB_ICONERROR);
        }
    }
}

std::string executeCommand(const std::string& command, bool isPowerShell = false) {
    std::string result;
    
    // Create pipes for stdout
    SECURITY_ATTRIBUTES saAttr;
    saAttr.nLength = sizeof(SECURITY_ATTRIBUTES);
    saAttr.bInheritHandle = TRUE;
    saAttr.lpSecurityDescriptor = NULL;
    
    HANDLE hReadPipe, hWritePipe;
    if (!CreatePipe(&hReadPipe, &hWritePipe, &saAttr, 0)) {
        return "";
    }
    
    // Ensure read handle is not inherited
    SetHandleInformation(hReadPipe, HANDLE_FLAG_INHERIT, 0);
    
    // Setup startup info
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.hStdError = hWritePipe;
    si.hStdOutput = hWritePipe;
    si.dwFlags |= STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;  // Hide window
    
    ZeroMemory(&pi, sizeof(pi));
    
    // Build command line
    std::string cmdLine;
    if (isPowerShell) {
        cmdLine = "powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -WindowStyle Hidden -Command \"" + command + "\"";
    } else {
        cmdLine = "cmd.exe /c " + command;
    }
    
    // Create process
    if (CreateProcessA(NULL,
                       const_cast<char*>(cmdLine.c_str()),
                       NULL,
                       NULL,
                       TRUE,
                       CREATE_NO_WINDOW,  // No console window
                       NULL,
                       NULL,
                       &si,
                       &pi)) {
        
        // Close write end of pipe
        CloseHandle(hWritePipe);
        
        // Read output
        char buffer[4096];
        DWORD bytesRead;
        
        while (ReadFile(hReadPipe, buffer, sizeof(buffer) - 1, &bytesRead, NULL) && bytesRead > 0) {
            buffer[bytesRead] = '\0';
            result += buffer;
        }
        
        // Wait for process to complete
        WaitForSingleObject(pi.hProcess, INFINITE);
        
        // Close handles
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
    
    CloseHandle(hReadPipe);
    
    return result;
}

std::string executePowerShell(const std::string& command) {
    return executeCommand(command, true);
}

// GUI Functions
void LogMessage(const std::string& message, bool isError) {
    std::lock_guard<std::mutex> lock(g_logMutex);
    
    // Get current text length
    int textLength = GetWindowTextLength(g_hLogEdit);
    
    // Move caret to end
    SendMessage(g_hLogEdit, EM_SETSEL, textLength, textLength);
    
    // Set color
    CHARFORMAT2 cf;
    memset(&cf, 0, sizeof(cf));
    cf.cbSize = sizeof(cf);
    cf.dwMask = CFM_COLOR;
    cf.crTextColor = isError ? RGB(255, 0, 0) : RGB(0, 0, 0);
    SendMessage(g_hLogEdit, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
    
    // Add timestamp
    SYSTEMTIME st;
    GetLocalTime(&st);
    char timestamp[32];
    sprintf(timestamp, "[%02d:%02d:%02d] ", st.wHour, st.wMinute, st.wSecond);
    
    // Insert text
    std::string fullMessage = timestamp + message + "\r\n";
    SendMessage(g_hLogEdit, EM_REPLACESEL, FALSE, (LPARAM)fullMessage.c_str());
    
    // Scroll to bottom
    SendMessage(g_hLogEdit, WM_VSCROLL, SB_BOTTOM, 0);
}

void SetStatus(const std::string& status) {
    // Only update if text actually changed
    char currentText[256];
    GetWindowTextA(g_hStatusText, currentText, sizeof(currentText));
    
    if (status != currentText) {
        SetWindowTextA(g_hStatusText, status.c_str());
    }
}

void EnableControls(bool enable) {
    EnableWindow(g_hSizeEdit, enable);
    EnableWindow(g_hStartButton, enable);
    EnableWindow(g_hExitButton, enable);
    EnableWindow(g_hDeleteIsoCheck, enable);
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

void UpdateDiskInfo() {
    g_cDriveInfo = getCDriveInfo();
    
    char diskInfo[512];
    sprintf(diskInfo, 
        "C: Drive Information:\r\n"
        "Total Size: %.2f GB\r\n"
        "Free Space: %.2f GB\r\n"
        "File System: %s\r\n"
        "Disk Number: %d\r\n"
        "Partition Number: %d",
        g_cDriveInfo.total_gb,
        g_cDriveInfo.free_gb,
        g_cDriveInfo.filesystem.c_str(),
        g_cDriveInfo.disk_number,
        g_cDriveInfo.partition_number);
    
    SetWindowTextA(g_hDiskInfo, diskInfo);
}

bool downloadWithProgress(const std::string& url, const std::string& destination) {
    LogMessage("Downloading from: " + url);
    
    HINTERNET hInternet = InternetOpenA("MintInstaller/1.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!hInternet) {
        LogMessage("Failed to initialize WinINet", true);
        return false;
    }
    
    HINTERNET hUrl = InternetOpenUrlA(hInternet, url.c_str(), NULL, 0, INTERNET_FLAG_RELOAD, 0);
    if (!hUrl) {
        InternetCloseHandle(hInternet);
        LogMessage("Failed to open URL", true);
        return false;
    }
    
    // Get file size
    char sizeBuffer[32];
    DWORD sizeBufferLen = sizeof(sizeBuffer);
    DWORD index = 0;
    HttpQueryInfoA(hUrl, HTTP_QUERY_CONTENT_LENGTH, sizeBuffer, &sizeBufferLen, &index);
    
    long long totalSize = std::stoll(sizeBuffer);
    long long downloadedSize = 0;
    
    // Set progress bar range
    SendMessage(g_hProgressBar, PBM_SETRANGE32, 0, 100);
    
    std::ofstream outFile(destination, std::ios::binary);
    if (!outFile) {
        InternetCloseHandle(hUrl);
        InternetCloseHandle(hInternet);
        LogMessage("Failed to create output file", true);
        return false;
    }
    
    const int bufferSize = 32768;  // Larger buffer for better performance
    char buffer[bufferSize];
    DWORD bytesRead;
    
    // Variables for update throttling
    auto lastUpdateTime = std::chrono::steady_clock::now();
    const auto updateInterval = std::chrono::milliseconds(100);  // Update every 100ms
    int lastPercent = -1;
    
    while (InternetReadFile(hUrl, buffer, bufferSize, &bytesRead) && bytesRead > 0) {
        outFile.write(buffer, bytesRead);
        downloadedSize += bytesRead;
        
        // Check if we should update the UI
        auto currentTime = std::chrono::steady_clock::now();
        if (currentTime - lastUpdateTime >= updateInterval) {
            int percent = (int)((double)downloadedSize * 100.0 / totalSize);
            
            // Only update if percentage changed
            if (percent != lastPercent) {
                SendMessage(g_hProgressBar, PBM_SETPOS, percent, 0);
                
                // Update status text
                char status[256];
                sprintf(status, "Downloading: %d%% - %lld/%lld MB", 
                        percent, downloadedSize / (1024 * 1024), totalSize / (1024 * 1024));
                SetStatus(status);
                
                lastPercent = percent;
            }
            
            lastUpdateTime = currentTime;
        }
    }
    
    // Final update
    SendMessage(g_hProgressBar, PBM_SETPOS, 100, 0);
    SetStatus("Download complete");
    
    outFile.close();
    InternetCloseHandle(hUrl);
    InternetCloseHandle(hInternet);
    
    // Reset progress bar
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    SendMessage(g_hProgressBar, PBM_SETPOS, 0, 0);
    
    return true;
}

bool shrinkCPartition(double sizeToShrinkGB) {
    LogMessage("Shrinking C: partition by " + std::to_string(sizeToShrinkGB) + " GB...");
    
    int sizeMB = (int)(sizeToShrinkGB * 1024);
    
    // Create diskpart script
    std::string tempPath = std::getenv("TEMP") ? std::getenv("TEMP") : ".";
    std::string scriptPath = tempPath + "\\shrink_script.txt";
    
    std::ofstream script(scriptPath);
    script << "select volume c" << std::endl;
    script << "shrink desired=" << sizeMB << std::endl;
    script << "exit" << std::endl;
    script.close();
    
    // Execute diskpart with hidden window
    std::string command = "diskpart /s \"" + scriptPath + "\"";
    std::string result = executeCommand(command, false);
    
    // Clean up
    std::remove(scriptPath.c_str());
    
    if (result.find("successfully") != std::string::npos) {
        LogMessage("C: partition shrunk successfully!");
        return true;
    }
    
    LogMessage("Failed to shrink partition", true);
    return false;
}

std::string createNewPartition(int diskNumber, double sizeGB, const std::string& label = "LINUXMINT") {
    LogMessage("Creating new " + std::to_string(sizeGB) + " GB partition...");
    
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
    
    // Execute diskpart with hidden window
    std::string command = "diskpart /s \"" + scriptPath + "\"";
    std::string result = executeCommand(command, false);
    
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
                        LogMessage("New partition created and assigned to " + drive);
                        return drive;
                    }
                }
            }
        }
    }
    
    LogMessage("Failed to create partition", true);
    return "";
}

std::string mountISO(const std::string& isoPath) {
    LogMessage("Mounting ISO...");
    
    std::string psCmd = "(Mount-DiskImage -ImagePath \\\"" + isoPath + 
                        "\\\" -PassThru | Get-Volume).DriveLetter";
    std::string result = executePowerShell(psCmd);
    
    // Remove whitespace
    result.erase(std::remove_if(result.begin(), result.end(), ::isspace), result.end());
    
    if (!result.empty()) {
        std::string mountedPath = result + ":";
        LogMessage("ISO mounted at " + mountedPath);
        return mountedPath;
    }
    
    LogMessage("Failed to mount ISO!", true);
    return "";
}

void unmountISO(const std::string& isoPath) {
    LogMessage("Unmounting ISO...");
    std::string psCmd = "Dismount-DiskImage -ImagePath \\\"" + isoPath + "\\\"";
    executePowerShell(psCmd);
}

bool copyFiles(const std::string& source, const std::string& target) {
    LogMessage("Copying Linux Mint files to " + target + "...");
    LogMessage("This may take 10-20 minutes...");
    
    // Build robocopy command
    std::string robocopyCmd = "robocopy \"" + source + "\" \"" + target + 
                              "\" /E /R:3 /W:5 /NP /NFL /NDL /ETA";
    
    LogMessage("Starting file copy...");
    
    // Execute robocopy with hidden window
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    
    ZeroMemory(&pi, sizeof(pi));
    
    if (CreateProcessA(NULL,
                       const_cast<char*>(robocopyCmd.c_str()),
                       NULL,
                       NULL,
                       FALSE,
                       CREATE_NO_WINDOW,
                       NULL,
                       NULL,
                       &si,
                       &pi)) {
        
        // Wait for robocopy to complete
        WaitForSingleObject(pi.hProcess, INFINITE);
        
        // Get exit code
        DWORD exitCode;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        
        // Robocopy exit codes: 0-7 are success codes
        if (exitCode >= 8) {
            LogMessage("Failed to copy files! Exit code: " + std::to_string(exitCode), true);
            return false;
        }
    } else {
        LogMessage("Failed to start file copy process!", true);
        return false;
    }
    
    LogMessage("Files copied successfully!");
    
    // Remove read-only attributes with hidden window
    LogMessage("Removing read-only attributes...");
    std::string attribCmd = "attrib -R \"" + target + "\\*.*\" /S /D";
    executeCommand(attribCmd, false);
    
    return true;
}

void createBootInstructions(const std::string& targetDrive, int diskNumber) {
    std::string instructions = "UEFI Boot Setup Instructions for Linux Mint\n"
                              "==========================================\n"
                              "\n"
                              "Your Linux Mint bootable partition has been created successfully!\n"
                              "\n"
                              "Partition Details:\n"
                              "- Drive: " + targetDrive + "\n"
                              "- Disk: " + std::to_string(diskNumber) + "\n"
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
                              "   - Find the Linux Mint entry (may appear as UEFI OS)\n"
                              "   - Set it as the first boot priority\n"
                              "   - OR use the one-time boot menu (usually F12) to select it\n"
                              "\n"
                              "4. Important Settings:\n"
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
}

// Installation thread
DWORD WINAPI InstallationThread(LPVOID lpParam) {
    g_isRunning = true;
    EnableControls(false);
    
    try {
        // Get Linux size from edit control
        char sizeText[32];
        GetWindowTextA(g_hSizeEdit, sizeText, sizeof(sizeText));
        double linuxSize = std::stod(sizeText);
        double totalNeeded = linuxSize + MIN_PARTITION_SIZE_GB;
        
        // Check space
        if (g_cDriveInfo.free_gb < totalNeeded + 10) {
            LogMessage("Error: Not enough free space!", true);
            LogMessage("Need: " + std::to_string(totalNeeded + 10) + " GB", true);
            LogMessage("Have: " + std::to_string(g_cDriveInfo.free_gb) + " GB", true);
            EnableControls(true);
            g_isRunning = false;
            return 1;
        }
        
        // Download ISO
        std::string tempPath = std::getenv("TEMP") ? std::getenv("TEMP") : ".";
        g_isoPath = tempPath + "\\linuxmint-22.1.iso";
        
        if (!fs::exists(g_isoPath)) {
            SetStatus("Downloading Linux Mint ISO...");
            LogMessage("Downloading Linux Mint 22.1 ISO (approximately 2.9 GB)...");
            
            bool downloadSuccess = false;
            for (size_t i = 0; i < MINT_MIRRORS.size() && !downloadSuccess; i++) {
                LogMessage("Trying mirror " + std::to_string(i + 1) + "/" + 
                          std::to_string(MINT_MIRRORS.size()));
                downloadSuccess = downloadWithProgress(MINT_MIRRORS[i], g_isoPath);
                
                if (!downloadSuccess && i < MINT_MIRRORS.size() - 1) {
                    LogMessage("Trying next mirror...");
                }
            }
            
            if (!downloadSuccess) {
                LogMessage("Failed to download Linux Mint ISO!", true);
                EnableControls(true);
                g_isRunning = false;
                return 1;
            }
        } else {
            LogMessage("Using existing ISO at: " + g_isoPath);
        }
        
        // Shrink C: partition
        SetStatus("Shrinking C: partition...");
        if (!shrinkCPartition(totalNeeded)) {
            LogMessage("Failed to shrink C: partition!", true);
            LogMessage("You may need to:", true);
            LogMessage("1. Run disk cleanup", true);
            LogMessage("2. Disable hibernation (powercfg -h off)", true);
            LogMessage("3. Temporarily disable system restore", true);
            LogMessage("4. Reboot and try again", true);
            EnableControls(true);
            g_isRunning = false;
            return 1;
        }
        
        // Create new partition
        SetStatus("Creating new partition...");
        std::this_thread::sleep_for(std::chrono::seconds(5));
        
        std::string newDrive = createNewPartition(g_cDriveInfo.disk_number, MIN_PARTITION_SIZE_GB);
        if (newDrive.empty()) {
            LogMessage("Failed to create new partition!", true);
            EnableControls(true);
            g_isRunning = false;
            return 1;
        }
        
        // Mount ISO and copy files
        SetStatus("Mounting ISO...");
        std::string sourcePath = mountISO(g_isoPath);
        if (sourcePath.empty()) {
            LogMessage("Failed to mount ISO!", true);
            EnableControls(true);
            g_isRunning = false;
            return 1;
        }
        
        SetStatus("Copying files...");
        if (!copyFiles(sourcePath, newDrive)) {
            unmountISO(g_isoPath);
            LogMessage("Failed to copy files!", true);
            EnableControls(true);
            g_isRunning = false;
            return 1;
        }
        
        // Create boot files
        SetStatus("Creating boot configuration...");
        fs::create_directories(newDrive + "\\EFI\\BOOT");
        createBootInstructions(newDrive, g_cDriveInfo.disk_number);
        
        unmountISO(g_isoPath);
        
        // Success
        LogMessage("=====================================");
        LogMessage("Installation Complete!");
        LogMessage("=====================================");
        LogMessage("Linux Mint has been installed to drive " + newDrive);
        LogMessage("Reserved " + std::to_string(linuxSize) + " GB for full Linux installation");
        LogMessage("");
        LogMessage("*** IMPORTANT BOOT INSTRUCTIONS ***");
        LogMessage("The Windows Boot Manager was NOT modified.");
        LogMessage("To boot Linux Mint, use the UEFI boot menu:");
        LogMessage("1. Restart your computer");
        LogMessage("2. Press F2, F10, F12, DEL, or ESC during startup");
        LogMessage("3. Select the Linux Mint entry");
        LogMessage("");
        LogMessage("Instructions saved to:");
        LogMessage("- " + newDrive + "\\UEFI_BOOT_INSTRUCTIONS.txt");
        LogMessage("- Desktop\\Linux_Mint_Boot_Instructions.txt");
        
        SetStatus("Installation complete!");
        
        // Check if we should delete ISO
        if (SendMessage(g_hDeleteIsoCheck, BM_GETCHECK, 0, 0) == BST_CHECKED) {
            try {
                fs::remove(g_isoPath);
                LogMessage("ISO file deleted.");
            } catch (...) {
                LogMessage("Could not delete ISO file.");
            }
        }
        
    } catch (const std::exception& e) {
        LogMessage("Error: " + std::string(e.what()), true);
        SetStatus("Installation failed!");
    }
    
    EnableControls(true);
    g_isRunning = false;
    return 0;
}

// Window procedure
LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    switch (uMsg) {
    case WM_CREATE:
        InitializeControls(hwnd);
        UpdateDiskInfo();
        return 0;
        
    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case ID_BUTTON_START:
            if (!g_isRunning) {
                CreateThread(NULL, 0, InstallationThread, NULL, 0, NULL);
            }
            break;
            
        case ID_BUTTON_EXIT:
            if (g_isRunning) {
                if (MessageBoxA(hwnd, "Installation is in progress. Are you sure you want to exit?",
                               "Confirm Exit", MB_YESNO | MB_ICONWARNING) == IDYES) {
                    PostQuitMessage(0);
                }
            } else {
                PostQuitMessage(0);
            }
            break;
        }
        return 0;
        
    case WM_NOTIFY:
        if (((LPNMHDR)lParam)->idFrom == ID_SPIN_SIZE && 
            ((LPNMHDR)lParam)->code == UDN_DELTAPOS) {
            LPNMUPDOWN lpnmud = (LPNMUPDOWN)lParam;
            int value = GetDlgItemInt(hwnd, ID_EDIT_SIZE, NULL, FALSE);
            value -= lpnmud->iDelta;
            if (value < MIN_LINUX_SIZE_GB) value = MIN_LINUX_SIZE_GB;
            if (value > 100) value = 100;
            SetDlgItemInt(hwnd, ID_EDIT_SIZE, value, FALSE);
        }
        return 0;
        
    case WM_CTLCOLORSTATIC:
        {
            HDC hdc = (HDC)wParam;
            HWND hControl = (HWND)lParam;
            
            if (hControl == GetDlgItem(hwnd, ID_STATIC_HEADER)) {
                SetTextColor(hdc, RGB(0, 51, 153));
                SetBkMode(hdc, TRANSPARENT);
                return (LRESULT)GetStockObject(NULL_BRUSH);
            }
        }
        break;
        
    case WM_DESTROY:
        if (g_hHeaderFont) DeleteObject(g_hHeaderFont);
        if (g_hNormalFont) DeleteObject(g_hNormalFont);
        if (g_hIcon) DestroyIcon(g_hIcon);
        PostQuitMessage(0);
        return 0;
    }
    
    return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

void InitializeControls(HWND hwnd) {
    // Create fonts
    g_hHeaderFont = CreateFont(24, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               DEFAULT_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI");
    
    g_hNormalFont = CreateFont(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               DEFAULT_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI");
    
    // Header
    HWND hHeader = CreateWindow("STATIC", "Windows -> Linux Installer",
                                WS_CHILD | WS_VISIBLE | SS_CENTER,
                                10, 10, 660, 30,
                                hwnd, (HMENU)ID_STATIC_HEADER, NULL, NULL);
    SendMessage(hHeader, WM_SETFONT, (WPARAM)g_hHeaderFont, TRUE);
    
    // Status
    g_hStatusText = CreateWindow("STATIC", "Ready to install",
                                 WS_CHILD | WS_VISIBLE | SS_CENTER,
                                 10, 45, 660, 20,
                                 hwnd, (HMENU)ID_STATIC_STATUS, NULL, NULL);
    SendMessage(g_hStatusText, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
    
    // Disk info group
    CreateWindow("BUTTON", "Disk Information",
                 WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
                 10, 75, 320, 120,
                 hwnd, (HMENU)ID_STATIC_GROUP_DISK, NULL, NULL);
    
    g_hDiskInfo = CreateWindow("STATIC", "",
                               WS_CHILD | WS_VISIBLE | SS_LEFT,
                               20, 95, 300, 90,
                               hwnd, (HMENU)ID_STATIC_DISK_INFO, NULL, NULL);
    SendMessage(g_hDiskInfo, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
    
    // Size selection group
    CreateWindow("BUTTON", "Linux Partition Size",
                 WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
                 350, 75, 320, 120,
                 hwnd, (HMENU)ID_STATIC_GROUP_SIZE, NULL, NULL);
    
    CreateWindow("STATIC", "Size for Linux (GB):",
                 WS_CHILD | WS_VISIBLE | SS_LEFT,
                 360, 110, 150, 20,
                 hwnd, (HMENU)ID_STATIC_SIZE_LABEL, NULL, NULL);
    
    g_hSizeEdit = CreateWindow("EDIT", "30",
                               WS_CHILD | WS_VISIBLE | WS_BORDER | ES_NUMBER,
                               510, 108, 80, 24,
                               hwnd, (HMENU)ID_EDIT_SIZE, NULL, NULL);
    SendMessage(g_hSizeEdit, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
    
    // Spin control
    HWND hSpin = CreateWindow(UPDOWN_CLASS, NULL,
                              WS_CHILD | WS_VISIBLE | UDS_AUTOBUDDY | UDS_ALIGNRIGHT | UDS_ARROWKEYS,
                              0, 0, 0, 0,
                              hwnd, (HMENU)ID_SPIN_SIZE, NULL, NULL);
    SendMessage(hSpin, UDM_SETRANGE, 0, MAKELPARAM(100, MIN_LINUX_SIZE_GB));
    SendMessage(hSpin, UDM_SETPOS, 0, 30);
    
    CreateWindow("STATIC", "Minimum: 20 GB, Recommended: 30-50 GB",
                 WS_CHILD | WS_VISIBLE | SS_LEFT,
                 360, 140, 300, 20,
                 hwnd, NULL, NULL, NULL);
    
    // Progress bar
    g_hProgressBar = CreateWindow(PROGRESS_CLASS, NULL,
                                  WS_CHILD | WS_VISIBLE | PBS_SMOOTH,
                                  10, 205, 660, 25,
                                  hwnd, (HMENU)ID_PROGRESS_BAR, NULL, NULL);
    
    // Log window group
    CreateWindow("BUTTON", "Installation Log",
                 WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
                 10, 240, 660, 250,
                 hwnd, (HMENU)ID_STATIC_GROUP_LOG, NULL, NULL);
    
    // Load RichEdit
    LoadLibrary("Riched20.dll");
    
    g_hLogEdit = CreateWindow(RICHEDIT_CLASS, "",
                              WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL | 
                              ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL,
                              20, 260, 640, 220,
                              hwnd, (HMENU)ID_RICHEDIT_LOG, NULL, NULL);
    SendMessage(g_hLogEdit, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
    
    // Options
    g_hDeleteIsoCheck = CreateWindow("BUTTON", "Delete ISO file after installation",
                                     WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
                                     10, 500, 300, 25,
                                     hwnd, (HMENU)ID_CHECK_DELETE_ISO, NULL, NULL);
    SendMessage(g_hDeleteIsoCheck, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
    
    // Buttons
    g_hStartButton = CreateWindow("BUTTON", "Start Installation",
                                  WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                  380, 495, 140, 35,
                                  hwnd, (HMENU)ID_BUTTON_START, NULL, NULL);
    SendMessage(g_hStartButton, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
    
    g_hExitButton = CreateWindow("BUTTON", "Exit",
                                 WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                 530, 495, 140, 35,
                                 hwnd, (HMENU)ID_BUTTON_EXIT, NULL, NULL);
    SendMessage(g_hExitButton, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
}

// Main function
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    // Check if running as admin
    if (!isAdmin()) {
        MessageBoxA(NULL, "This program requires administrator privileges.\n"
                          "The program will now restart as administrator.",
                    "Administrator Required", MB_OK | MB_ICONINFORMATION);
        
        char exePath[MAX_PATH];
        GetModuleFileNameA(NULL, exePath, MAX_PATH);
        runAsAdmin(exePath);
        return 0;
    }
    
    // Allow this process to set foreground window
    AllowSetForegroundWindow(ASFW_ANY);
    
    // Initialize common controls
    INITCOMMONCONTROLSEX icex;
    icex.dwSize = sizeof(INITCOMMONCONTROLSEX);
    icex.dwICC = ICC_WIN95_CLASSES | ICC_UPDOWN_CLASS | ICC_PROGRESS_CLASS;
    InitCommonControlsEx(&icex);
    
    // Register window class
    const char* CLASS_NAME = "MintInstallerGUI";
    
    WNDCLASSEX wc = {0};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = hInstance;
    wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = CLASS_NAME;
    wc.hIconSm = LoadIcon(NULL, IDI_APPLICATION);
    
    if (!RegisterClassEx(&wc)) {
        MessageBoxA(NULL, "Window registration failed!", "Error", MB_OK | MB_ICONERROR);
        return 1;
    }
    
    // Create window with WS_EX_TOPMOST temporarily
    g_hWnd = CreateWindowEx(
        WS_EX_TOPMOST,
        CLASS_NAME,
        "Windows -> Linux Installer",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 700, 580,
        NULL,
        NULL,
        hInstance,
        NULL
    );
    
    if (g_hWnd == NULL) {
        MessageBoxA(NULL, "Window creation failed!", "Error", MB_OK | MB_ICONERROR);
        return 1;
    }
    
    // Center window
    RECT rcWindow, rcDesktop;
    GetWindowRect(g_hWnd, &rcWindow);
    GetWindowRect(GetDesktopWindow(), &rcDesktop);
    int x = (rcDesktop.right - (rcWindow.right - rcWindow.left)) / 2;
    int y = (rcDesktop.bottom - (rcWindow.bottom - rcWindow.top)) / 2;
    SetWindowPos(g_hWnd, NULL, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
    
    // Show window and bring to foreground
    ShowWindow(g_hWnd, SW_SHOW);
    UpdateWindow(g_hWnd);
    
    // Force window to foreground
    SetForegroundWindow(g_hWnd);
    SetActiveWindow(g_hWnd);
    SetFocus(g_hWnd);
    
    // Additional method to ensure foreground
    DWORD currentThreadId = GetCurrentThreadId();
    DWORD foregroundThreadId = GetWindowThreadProcessId(GetForegroundWindow(), NULL);
    
    if (currentThreadId != foregroundThreadId) {
        AttachThreadInput(currentThreadId, foregroundThreadId, TRUE);
        SetForegroundWindow(g_hWnd);
        AttachThreadInput(currentThreadId, foregroundThreadId, FALSE);
    }
    
    // Flash taskbar if still not in foreground
    if (GetForegroundWindow() != g_hWnd) {
        FLASHWINFO flash = {0};
        flash.cbSize = sizeof(FLASHWINFO);
        flash.hwnd = g_hWnd;
        flash.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
        flash.uCount = 1;
        flash.dwTimeout = 0;
        FlashWindowEx(&flash);
    }
    
    // Remove topmost after bringing to front
    SetWindowPos(g_hWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    
    // Message loop
    MSG msg = {0};
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    
    return msg.wParam;
}
