# Linux Mint 22.1 Partition Installer for Windows 11 UEFI Systems
# PowerShell GUI Version
# Run as Administrator: powershell -ExecutionPolicy Bypass -File mint_installer.ps1

#Requires -RunAsAdministrator
#Requires -Version 5.1

# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Global variables
$script:MinPartitionSizeGB = 7
$script:MinLinuxSizeGB = 20
$script:MintMirrors = @(
    "https://mirrors.kernel.org/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirror.csclub.uwaterloo.ca/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirrors.layeronline.com/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirror.arizona.edu/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso"
)

$script:IsoPath = "$env:TEMP\linuxmint-22.1.iso"
$script:IsRunning = $false

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows -> Linux Installer"
$form.Size = New-Object System.Drawing.Size(720, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.Icon = [System.Drawing.SystemIcons]::Application

# Create fonts
$headerFont = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$normalFont = New-Object System.Drawing.Font("Segoe UI", 9)
$boldFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

# Header label
$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Text = "Windows -> Linux Installer"
$headerLabel.Font = $headerFont
$headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 51, 153)
$headerLabel.Location = New-Object System.Drawing.Point(10, 10)
$headerLabel.Size = New-Object System.Drawing.Size(680, 30)
$headerLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($headerLabel)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready to install"
$statusLabel.Font = $normalFont
$statusLabel.Location = New-Object System.Drawing.Point(10, 45)
$statusLabel.Size = New-Object System.Drawing.Size(680, 20)
$statusLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($statusLabel)

# Disk info group
$diskGroup = New-Object System.Windows.Forms.GroupBox
$diskGroup.Text = "Disk Information"
$diskGroup.Font = $normalFont
$diskGroup.Location = New-Object System.Drawing.Point(10, 75)
$diskGroup.Size = New-Object System.Drawing.Size(330, 130)  # Increased height from 120 to 130
$form.Controls.Add($diskGroup)

# Disk info text
$diskInfoText = New-Object System.Windows.Forms.Label
$diskInfoText.Font = $normalFont
$diskInfoText.Location = New-Object System.Drawing.Point(10, 20)
$diskInfoText.Size = New-Object System.Drawing.Size(310, 100)  # Increased height from 90 to 100
$diskGroup.Controls.Add($diskInfoText)

# Size selection group
$sizeGroup = New-Object System.Windows.Forms.GroupBox
$sizeGroup.Text = "Linux Partition Size"
$sizeGroup.Font = $normalFont
$sizeGroup.Location = New-Object System.Drawing.Point(360, 75)
$sizeGroup.Size = New-Object System.Drawing.Size(330, 130)  # Increased to match disk group
$form.Controls.Add($sizeGroup)

# Size label
$sizeLabel = New-Object System.Windows.Forms.Label
$sizeLabel.Text = "Size for Linux (GB):"
$sizeLabel.Font = $normalFont
$sizeLabel.Location = New-Object System.Drawing.Point(10, 35)
$sizeLabel.Size = New-Object System.Drawing.Size(150, 20)
$sizeGroup.Controls.Add($sizeLabel)

# Size numeric up/down
$sizeNumeric = New-Object System.Windows.Forms.NumericUpDown
$sizeNumeric.Font = $normalFont
$sizeNumeric.Location = New-Object System.Drawing.Point(160, 33)
$sizeNumeric.Size = New-Object System.Drawing.Size(80, 24)
$sizeNumeric.Minimum = $script:MinLinuxSizeGB
$sizeNumeric.Maximum = 10000  # Allow up to 10TB
$sizeNumeric.Value = 30
$sizeGroup.Controls.Add($sizeNumeric)

# Size help label
$sizeHelpLabel = New-Object System.Windows.Forms.Label
$sizeHelpLabel.Text = "Minimum: 20 GB, Recommended: 30-50 GB"
$sizeHelpLabel.Font = $normalFont
$sizeHelpLabel.Location = New-Object System.Drawing.Point(10, 65)
$sizeHelpLabel.Size = New-Object System.Drawing.Size(310, 20)
$sizeGroup.Controls.Add($sizeHelpLabel)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 215)  # Moved down 10 pixels
$progressBar.Size = New-Object System.Drawing.Size(680, 25)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

# Log group
$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = "Installation Log"
$logGroup.Font = $normalFont
$logGroup.Location = New-Object System.Drawing.Point(10, 250)  # Moved down 10 pixels
$logGroup.Size = New-Object System.Drawing.Size(680, 250)  # Reduced height by 10
$form.Controls.Add($logGroup)

# Log text box
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(10, 20)
$logBox.Size = New-Object System.Drawing.Size(660, 220)  # Reduced height by 10
$logGroup.Controls.Add($logBox)

# Delete ISO checkbox
$deleteIsoCheck = New-Object System.Windows.Forms.CheckBox
$deleteIsoCheck.Text = "Delete ISO file after installation"
$deleteIsoCheck.Font = $normalFont
$deleteIsoCheck.Location = New-Object System.Drawing.Point(10, 510)
$deleteIsoCheck.Size = New-Object System.Drawing.Size(300, 25)
$form.Controls.Add($deleteIsoCheck)

# Start button
$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start Installation"
$startButton.Font = $boldFont
$startButton.Location = New-Object System.Drawing.Point(400, 505)
$startButton.Size = New-Object System.Drawing.Size(140, 35)
$startButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$startButton.ForeColor = [System.Drawing.Color]::White
$startButton.FlatStyle = "Flat"
$form.Controls.Add($startButton)

# Exit button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Font = $normalFont
$exitButton.Location = New-Object System.Drawing.Point(550, 505)
$exitButton.Size = New-Object System.Drawing.Size(140, 35)
$form.Controls.Add($exitButton)

# Helper functions
function Log-Message {
    param(
        [string]$Message,
        [switch]$Error
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $fullMessage = "[$timestamp] $Message"
    
    $logBox.AppendText("$fullMessage`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    
    if ($Error) {
        Write-Host $fullMessage -ForegroundColor Red
    } else {
        Write-Host $fullMessage
    }
}

function Set-Status {
    param([string]$Status)
    $statusLabel.Text = $Status
    $form.Refresh()
}

function Update-DiskInfo {
    try {
        $cDrive = Get-Partition -DriveLetter C -ErrorAction Stop | Select-Object -First 1
        $disk = Get-Disk -Number $cDrive.DiskNumber -ErrorAction Stop
        $volume = Get-Volume -DriveLetter C -ErrorAction Stop
        
        # Ensure we have the partition number
        $partitionNumber = if ($cDrive.PartitionNumber) { 
            $cDrive.PartitionNumber 
        } else { 
            # Fallback method to get partition number
            (Get-Partition -DiskNumber $cDrive.DiskNumber | Where-Object { $_.DriveLetter -eq 'C' }).PartitionNumber
        }
        
        $diskInfo = @"
C: Drive Information:
Total Size: $([math]::Round($volume.Size / 1GB, 2)) GB
Free Space: $([math]::Round($volume.SizeRemaining / 1GB, 2)) GB
File System: $($volume.FileSystem)
Disk Number: $($cDrive.DiskNumber)
Partition Number: $partitionNumber
"@
        
        $diskInfoText.Text = $diskInfo
        
        # Store for later use
        $script:CDriveInfo = @{
            DiskNumber = $cDrive.DiskNumber
            PartitionNumber = $partitionNumber
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
            TotalGB = [math]::Round($volume.Size / 1GB, 2)
        }
        
        # Update the maximum value for size selector based on available space
        # Account for ISO partition (7GB) and buffer (10GB)
        $maxAvailable = [math]::Floor($script:CDriveInfo.FreeGB - $script:MinPartitionSizeGB - 10)
        if ($maxAvailable -gt $script:MinLinuxSizeGB) {
            $sizeNumeric.Maximum = $maxAvailable
        }
    }
    catch {
        Log-Message "Error getting disk information: $_" -Error
        
        # Try alternative method
        try {
            $volume = Get-Volume -DriveLetter C
            $partition = Get-Partition -DriveLetter C
            
            $diskInfo = @"
C: Drive Information:
Total Size: $([math]::Round($volume.Size / 1GB, 2)) GB
Free Space: $([math]::Round($volume.SizeRemaining / 1GB, 2)) GB
File System: $($volume.FileSystem)
Disk Number: $(if ($partition.DiskNumber -ne $null) { $partition.DiskNumber } else { "Unknown" })
Partition Number: $(if ($partition.PartitionNumber -ne $null) { $partition.PartitionNumber } else { "Unknown" })
"@
            
            $diskInfoText.Text = $diskInfo
            
            # Store what we can get
            $script:CDriveInfo = @{
                DiskNumber = if ($partition.DiskNumber -ne $null) { $partition.DiskNumber } else { 0 }
                PartitionNumber = if ($partition.PartitionNumber -ne $null) { $partition.PartitionNumber } else { 0 }
                FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
                TotalGB = [math]::Round($volume.Size / 1GB, 2)
            }
            
            # Update maximum for size selector
            $maxAvailable = [math]::Floor($script:CDriveInfo.FreeGB - $script:MinPartitionSizeGB - 10)
            if ($maxAvailable -gt $script:MinLinuxSizeGB) {
                $sizeNumeric.Maximum = $maxAvailable
            }
        }
        catch {
            $diskInfoText.Text = "Error retrieving disk information"
        }
    }
}

function Download-LinuxMint {
    param([string]$Destination)
    
    Log-Message "Downloading Linux Mint 22.1 ISO (approximately 2.9 GB)..."
    Log-Message "This may take a while depending on your internet speed..."
    
    foreach ($i in 0..($script:MintMirrors.Count - 1)) {
        $mirror = $script:MintMirrors[$i]
        Log-Message "Trying mirror $($i + 1)/$($script:MintMirrors.Count): $($mirror.Split('/')[2])"
        Set-Status "Connecting to mirror..."
        
        try {
            # Use .NET HttpClient for better control
            Add-Type -AssemblyName System.Net.Http
            
            $httpClient = New-Object System.Net.Http.HttpClient
            $httpClient.Timeout = [TimeSpan]::FromMinutes(60)
            
            # Get the response
            $response = $httpClient.GetAsync($mirror, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
            
            if ($response.IsSuccessStatusCode) {
                $totalBytes = $response.Content.Headers.ContentLength
                $totalMB = [math]::Round($totalBytes / 1MB, 1)
                Log-Message "File size: $totalMB MB"
                
                # Open file stream
                $fileStream = [System.IO.File]::Create($Destination)
                $downloadStream = $response.Content.ReadAsStreamAsync().Result
                
                # Buffer for copying
                $buffer = New-Object byte[] 81920  # 80KB buffer
                $totalRead = 0
                $lastUpdate = [DateTime]::Now
                $updateInterval = [TimeSpan]::FromMilliseconds(500)
                
                Set-Status "Downloading..."
                
                # Read and write in chunks
                while ($true) {
                    $bytesRead = $downloadStream.Read($buffer, 0, $buffer.Length)
                    
                    if ($bytesRead -eq 0) {
                        break
                    }
                    
                    $fileStream.Write($buffer, 0, $bytesRead)
                    $totalRead += $bytesRead
                    
                    # Update progress at intervals
                    $now = [DateTime]::Now
                    if (($now - $lastUpdate) -gt $updateInterval) {
                        $percent = [int](($totalRead / $totalBytes) * 100)
                        $mbDownloaded = [math]::Round($totalRead / 1MB, 1)
                        
                        $progressBar.Value = $percent
                        Set-Status "Downloading: $percent% - $mbDownloaded MB / $totalMB MB"
                        
                        # Keep UI responsive
                        [System.Windows.Forms.Application]::DoEvents()
                        $lastUpdate = $now
                    }
                }
                
                # Close streams
                $fileStream.Close()
                $downloadStream.Close()
                $response.Dispose()
                $httpClient.Dispose()
                
                # Final progress update
                $progressBar.Value = 100
                Set-Status "Download complete!"
                Start-Sleep -Milliseconds 500
                $progressBar.Value = 0
                
                # Verify file
                $fileInfo = Get-Item $Destination
                $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
                Log-Message "Downloaded file size: $fileSizeGB GB"
                
                if ($fileInfo.Length -lt 2GB) {
                    Log-Message "File size too small, download may be corrupted" -Error
                    Remove-Item $Destination -Force
                    continue
                }
                
                return $true
            } else {
                throw "HTTP Error: $($response.StatusCode)"
            }
        }
        catch {
            Log-Message "Download failed: $_" -Error
            
            if (Test-Path $Destination) {
                try {
                    Remove-Item $Destination -Force -ErrorAction SilentlyContinue
                    Log-Message "Removed incomplete download"
                } catch {}
            }
            
            if ($i -lt $script:MintMirrors.Count - 1) {
                Log-Message "Trying next mirror..."
            }
        }
    }
    
    # If all mirrors fail, provide manual download option
    Log-Message "All automatic download attempts failed" -Error
    $response = [System.Windows.Forms.MessageBox]::Show(
        "Automatic download failed. Would you like to:`n`n" +
        "- Download manually from your browser?`n" +
        "- Place the file at: $Destination`n" +
        "- Then click 'Retry' in the installer`n`n" +
        "Click Yes to open the download page, No to cancel",
        "Download Failed",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    
    if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process "https://linuxmint.com/download.php"
        Log-Message "Please download Linux Mint 22.1 Cinnamon 64-bit and save it as:"
        Log-Message $Destination
        Log-Message "Then run the installer again"
    }
    
    return $false
}

function Start-Installation {
    if ($script:IsRunning) {
        return
    }
    
    $script:IsRunning = $true
    $startButton.Enabled = $false
    $exitButton.Enabled = $false
    $sizeNumeric.Enabled = $false
    $deleteIsoCheck.Enabled = $false
    
    try {
        # Get Linux size
        $linuxSizeGB = $sizeNumeric.Value
        $totalNeededGB = $linuxSizeGB + $script:MinPartitionSizeGB
        
        # Check space
        if ($script:CDriveInfo.FreeGB -lt ($totalNeededGB + 10)) {
            Log-Message "Error: Not enough free space!" -Error
            Log-Message "Need: $($totalNeededGB + 10) GB" -Error
            Log-Message "Have: $($script:CDriveInfo.FreeGB) GB" -Error
            return
        }
        
        # Download ISO if needed
        if (Test-Path $script:IsoPath) {
            Log-Message "Found existing ISO at: $script:IsoPath"
            
            # Verify existing ISO
            try {
                $fileInfo = Get-Item $script:IsoPath
                $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
                Log-Message "Existing ISO size: $fileSizeGB GB"
                
                if ($fileInfo.Length -lt 2GB) {
                    Log-Message "Existing ISO appears corrupted (too small)" -Error
                    Log-Message "Deleting corrupted file..." -Error
                    Remove-Item $script:IsoPath -Force
                    
                    Set-Status "Re-downloading Linux Mint ISO..."
                    if (-not (Download-LinuxMint -Destination $script:IsoPath)) {
                        Log-Message "Failed to download Linux Mint ISO!" -Error
                        return
                    }
                } else {
                    # Try to verify the ISO is valid
                    try {
                        # Test if we can get disk image info
                        $testMount = Get-DiskImage -ImagePath $script:IsoPath -ErrorAction Stop
                        Log-Message "ISO verification passed"
                    }
                    catch {
                        Log-Message "Existing ISO appears corrupted" -Error
                        Log-Message "Error: $_" -Error
                        
                        $response = [System.Windows.Forms.MessageBox]::Show(
                            "The existing ISO file appears to be corrupted. Would you like to re-download it?",
                            "Corrupted ISO",
                            [System.Windows.Forms.MessageBoxButtons]::YesNo,
                            [System.Windows.Forms.MessageBoxIcon]::Warning
                        )
                        
                        if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
                            Remove-Item $script:IsoPath -Force
                            Set-Status "Re-downloading Linux Mint ISO..."
                            if (-not (Download-LinuxMint -Destination $script:IsoPath)) {
                                Log-Message "Failed to download Linux Mint ISO!" -Error
                                return
                            }
                        } else {
                            Log-Message "Installation cancelled by user" -Error
                            return
                        }
                    }
                }
            }
            catch {
                Log-Message "Error checking existing ISO: $_" -Error
                return
            }
        } else {
            Set-Status "Downloading Linux Mint ISO..."
            if (-not (Download-LinuxMint -Destination $script:IsoPath)) {
                Log-Message "Failed to download Linux Mint ISO!" -Error
                return
            }
        }
        
        # Shrink C: partition
        Set-Status "Shrinking C: partition..."
        Log-Message "Shrinking C: partition by $totalNeededGB GB..."
        
        try {
            $currentSize = (Get-Partition -DriveLetter C).Size
            $newSize = $currentSize - ($totalNeededGB * 1GB)
            
            Resize-Partition -DriveLetter C -Size $newSize -ErrorAction Stop
            Log-Message "C: partition shrunk successfully!"
        }
        catch {
            # Try diskpart as fallback
            Log-Message "Trying diskpart method..."
            $sizeMB = [int]($totalNeededGB * 1024)
            $diskpartScript = @"
select volume c
shrink desired=$sizeMB
exit
"@
            $scriptPath = "$env:TEMP\shrink_script.txt"
            $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
            
            $result = diskpart /s $scriptPath
            Remove-Item $scriptPath -Force
            
            if ($result -match "successfully") {
                Log-Message "C: partition shrunk successfully!"
            } else {
                Log-Message "Failed to shrink C: partition!" -Error
                Log-Message "You may need to: 1) Run disk cleanup 2) Disable hibernation (powercfg -h off) 3) Reboot" -Error
                return
            }
        }
        
        # Wait for Windows to recognize changes
        Start-Sleep -Seconds 5
        
        # Create new partition
        Set-Status "Creating new partition..."
        Log-Message "Creating new $script:MinPartitionSizeGB GB partition..."
        
        try {
            # Create partition
            $newPartition = New-Partition -DiskNumber $script:CDriveInfo.DiskNumber `
                -Size ($script:MinPartitionSizeGB * 1GB) `
                -AssignDriveLetter `
                -ErrorAction Stop
            
            $driveLetter = $newPartition.DriveLetter
            
            # Format as FAT32
            Format-Volume -DriveLetter $driveLetter `
                -FileSystem FAT32 `
                -NewFileSystemLabel "LINUXMINT" `
                -Confirm:$false `
                -ErrorAction Stop
            
            Log-Message "New partition created and assigned to ${driveLetter}:"
            $script:NewDrive = "${driveLetter}:"
        }
        catch {
            Log-Message "Failed to create partition: $_" -Error
            return
        }
        
        # Mount ISO
        Set-Status "Mounting ISO..."
        Log-Message "Mounting ISO..."
        
        try {
            # Verify ISO exists and is readable
            if (-not (Test-Path $script:IsoPath)) {
                Log-Message "ISO file not found at: $script:IsoPath" -Error
                return
            }
            
            $mountResult = Mount-DiskImage -ImagePath $script:IsoPath -PassThru -ErrorAction Stop
            
            # Wait a moment for mount to complete
            Start-Sleep -Seconds 2
            
            # Get the mounted volume
            $isoVolume = Get-Volume -DiskImage $mountResult -ErrorAction Stop | Select-Object -First 1
            
            if (-not $isoVolume) {
                Log-Message "Failed to get volume information from mounted ISO" -Error
                Dismount-DiskImage -ImagePath $script:IsoPath -ErrorAction SilentlyContinue
                return
            }
            
            $sourceDrive = "$($isoVolume.DriveLetter):"
            Log-Message "ISO mounted at $sourceDrive"
            
            # Verify mount by checking for expected files
            if (-not (Test-Path "$sourceDrive\casper\vmlinuz")) {
                Log-Message "Warning: ISO might not be a valid Linux Mint image (missing casper/vmlinuz)" -Error
                
                $response = [System.Windows.Forms.MessageBox]::Show(
                    "The ISO doesn't appear to be a valid Linux Mint image. Continue anyway?",
                    "Invalid ISO",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                
                if ($response -ne [System.Windows.Forms.DialogResult]::Yes) {
                    Dismount-DiskImage -ImagePath $script:IsoPath
                    return
                }
            }
        }
        catch {
            Log-Message "Failed to mount ISO: $_" -Error
            
            # If mount failed, ISO is likely corrupted
            $response = [System.Windows.Forms.MessageBox]::Show(
                "Failed to mount the ISO file. It may be corrupted. Would you like to delete it and re-download?",
                "Mount Failed",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            
            if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Remove-Item $script:IsoPath -Force
                    Log-Message "Deleted corrupted ISO"
                    
                    Set-Status "Re-downloading Linux Mint ISO..."
                    if (Download-LinuxMint -Destination $script:IsoPath) {
                        # Try mounting again
                        Start-Installation
                        return
                    }
                } catch {
                    Log-Message "Error handling corrupted ISO: $_" -Error
                }
            }
            return
        }
        
        # Copy files
        Set-Status "Copying files..."
        Log-Message "Copying Linux Mint files to $script:NewDrive..."
        Log-Message "This may take 10-20 minutes..."
        
        try {
            # Use robocopy for reliable copying
            $robocopyArgs = @(
                $sourceDrive,
                $script:NewDrive,
                "/E",      # Copy subdirectories including empty
                "/R:3",    # Retry 3 times
                "/W:5",    # Wait 5 seconds between retries
                "/NP",     # No progress percentage
                "/NFL",    # No file list
                "/NDL",    # No directory list
                "/ETA"     # Show estimated time
            )
            
            $result = robocopy @robocopyArgs
            
            # Robocopy exit codes 0-7 are success
            if ($LASTEXITCODE -ge 8) {
                Log-Message "Failed to copy files! Exit code: $LASTEXITCODE" -Error
                return
            }
            
            Log-Message "Files copied successfully!"
            
            # Remove read-only attributes
            Log-Message "Removing read-only attributes..."
            attrib -R "$script:NewDrive\*.*" /S /D
        }
        catch {
            Log-Message "Error during file copy: $_" -Error
            return
        }
        finally {
            # Unmount ISO
            Dismount-DiskImage -ImagePath $script:IsoPath
        }
        
        # Create boot configuration
        Set-Status "Creating boot configuration..."
        Log-Message "Creating boot configuration..."
        
        # Create EFI directory if needed
        $efiPath = "$script:NewDrive\EFI\BOOT"
        if (-not (Test-Path $efiPath)) {
            New-Item -Path $efiPath -ItemType Directory -Force
        }
        
        # Create boot instructions
        $instructions = @"
UEFI Boot Setup Instructions for Linux Mint
==========================================

Your Linux Mint bootable partition has been created successfully!

Partition Details:
- Drive: $script:NewDrive
- Disk: $($script:CDriveInfo.DiskNumber)

To boot Linux Mint:

1. Restart your computer

2. Access UEFI/BIOS settings:
   - During startup, press the BIOS key (usually F2, F10, F12, DEL, or ESC)
   - The exact key depends on your motherboard manufacturer

3. In UEFI settings:
   - Look for "Boot" or "Boot Order" section
   - Find the Linux Mint entry (may appear as "UEFI: $script:NewDrive LINUXMINT")
   - Set it as the first boot priority
   - OR use the one-time boot menu (usually F12) to select it

4. Important Settings:
   - Disable Secure Boot (if enabled)
   - Ensure UEFI mode is enabled (not Legacy/CSM)
   - Save changes and exit

5. The system should now boot into Linux Mint Live environment

Note: The Windows Boot Manager entry was NOT modified to prevent boot issues.
      Use the UEFI boot menu to select between Windows and Linux Mint.

Troubleshooting:
- If you don't see the Linux Mint option, try disabling Fast Boot
- Some systems require you to manually add a boot entry pointing to:
  \EFI\BOOT\BOOTx64.EFI on the LINUXMINT partition
"@
        
        # Save instructions
        $instructions | Out-File -FilePath "$script:NewDrive\UEFI_BOOT_INSTRUCTIONS.txt" -Encoding UTF8
        $instructions | Out-File -FilePath "$env:USERPROFILE\Desktop\Linux_Mint_Boot_Instructions.txt" -Encoding UTF8
        
        # Success
        Log-Message "====================================="
        Log-Message "Installation Complete!"
        Log-Message "====================================="
        Log-Message "Linux Mint has been installed to drive $script:NewDrive"
        Log-Message "Reserved $linuxSizeGB GB for full Linux installation"
        Log-Message ""
        Log-Message "*** IMPORTANT BOOT INSTRUCTIONS ***"
        Log-Message "The Windows Boot Manager was NOT modified."
        Log-Message "To boot Linux Mint, use the UEFI boot menu:"
        Log-Message "1. Restart your computer"
        Log-Message "2. Press F2, F10, F12, DEL, or ESC during startup"
        Log-Message "3. Select the Linux Mint entry"
        Log-Message "4. Make sure Secure Boot is disabled"
        Log-Message ""
        Log-Message "Instructions saved to:"
        Log-Message "- $script:NewDrive\UEFI_BOOT_INSTRUCTIONS.txt"
        Log-Message "- Desktop\Linux_Mint_Boot_Instructions.txt"
        
        Set-Status "Installation complete!"
        
        # Delete ISO if requested
        if ($deleteIsoCheck.Checked) {
            try {
                Remove-Item $script:IsoPath -Force
                Log-Message "ISO file deleted."
            }
            catch {
                Log-Message "Could not delete ISO file."
            }
        }
    }
    catch {
        Log-Message "Installation error: $_" -Error
        Set-Status "Installation failed!"
    }
    finally {
        $script:IsRunning = $false
        $startButton.Enabled = $true
        $exitButton.Enabled = $true
        $sizeNumeric.Enabled = $true
        $deleteIsoCheck.Enabled = $true
    }
}

# Event handlers
$startButton.Add_Click({
    Start-Installation
})

$exitButton.Add_Click({
    if ($script:IsRunning) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Installation is in progress. Are you sure you want to exit?",
            "Confirm Exit",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $form.Close()
        }
    } else {
        $form.Close()
    }
})

# Initialize
Update-DiskInfo

# Check if running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    [System.Windows.Forms.MessageBox]::Show(
        "This script must be run as Administrator.`n`nRight-click the script and select 'Run as Administrator'",
        "Administrator Required",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit
}

# Show form
$form.ShowDialog() | Out-Null