# Linux Installer for Windows 11 UEFI Systems - Enhanced Edition with Auto-Restart
# PowerShell GUI Version - Fixed unit conversions for proper partition placement
# FIXED: Boot loop prevention with proper marker file handling
# Run as Administrator: powershell -ExecutionPolicy Bypass -File linux_installer.ps1

#Requires -RunAsAdministrator
#Requires -Version 5.1

# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Global variables
$script:MinPartitionSizeGB = 7
$script:MinLinuxSizeGB = 20
$script:KubuntuMirrors = @(
    "https://cdimage.ubuntu.com/kubuntu/releases/25.04/release/kubuntu-25.04-desktop-amd64.iso",
    "https://www.mirrorservice.org/sites/cdimage.ubuntu.com/cdimage/kubuntu/releases/25.04/release/kubuntu-25.04-desktop-amd64.iso"
)
$script:MintMirrors = @(
    "https://mirrors.kernel.org/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirror.csclub.uwaterloo.ca/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirrors.layeronline.com/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso",
    "https://mirror.arizona.edu/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso"
)

# Official SHA256 checksums
$script:Checksums = @{
    "Kubuntu" = "701f1fd796ed6d5867f54af0e2dceac7b7f01a9f975fda3423e9d0e97da10ba8"
    "Mint" = "ccf482436df954c0ad6d41123a49fde79352ca71f7a684a97d5e0a0c39d7f39f"
}

$script:IsoPath = ""
$script:CustomIsoPath = ""
$script:IsRunning = $false
$script:SelectedDistro = "Kubuntu"

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "USB-less Linux Installer for Windows"
$form.Size = New-Object System.Drawing.Size(720, 750)
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
$headerLabel.Text = "USB-less Linux Installer for Windows"
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

# Distribution selection group
$distroGroup = New-Object System.Windows.Forms.GroupBox
$distroGroup.Text = "Select Linux Distribution"
$distroGroup.Font = $normalFont
$distroGroup.Location = New-Object System.Drawing.Point(10, 75)
$distroGroup.Size = New-Object System.Drawing.Size(680, 100)
$form.Controls.Add($distroGroup)

# Kubuntu radio button
$kubuntuRadio = New-Object System.Windows.Forms.RadioButton
$kubuntuRadio.Text = "Kubuntu 25.04 (KDE Plasma)"
$kubuntuRadio.Font = $normalFont
$kubuntuRadio.Location = New-Object System.Drawing.Point(20, 25)
$kubuntuRadio.Size = New-Object System.Drawing.Size(280, 20)
$kubuntuRadio.Checked = $true
$distroGroup.Controls.Add($kubuntuRadio)

# Mint radio button
$mintRadio = New-Object System.Windows.Forms.RadioButton
$mintRadio.Text = "Linux Mint 22.1 (Cinnamon)"
$mintRadio.Font = $normalFont
$mintRadio.Location = New-Object System.Drawing.Point(350, 25)
$mintRadio.Size = New-Object System.Drawing.Size(280, 20)
$distroGroup.Controls.Add($mintRadio)

# Custom ISO radio button
$customRadio = New-Object System.Windows.Forms.RadioButton
$customRadio.Text = "Custom ISO file"
$customRadio.Font = $normalFont
$customRadio.Location = New-Object System.Drawing.Point(20, 50)
$customRadio.Size = New-Object System.Drawing.Size(120, 20)
$distroGroup.Controls.Add($customRadio)

# Custom ISO path textbox
$customIsoTextbox = New-Object System.Windows.Forms.TextBox
$customIsoTextbox.Font = $normalFont
$customIsoTextbox.Location = New-Object System.Drawing.Point(150, 48)
$customIsoTextbox.Size = New-Object System.Drawing.Size(400, 24)
$customIsoTextbox.ReadOnly = $true
$customIsoTextbox.Enabled = $false
$distroGroup.Controls.Add($customIsoTextbox)

# Browse button
$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse..."
$browseButton.Font = $normalFont
$browseButton.Location = New-Object System.Drawing.Point(560, 47)
$browseButton.Size = New-Object System.Drawing.Size(100, 26)
$browseButton.Enabled = $false
$distroGroup.Controls.Add($browseButton)

# Disk info group
$diskGroup = New-Object System.Windows.Forms.GroupBox
$diskGroup.Text = "Disk Information"
$diskGroup.Font = $normalFont
$diskGroup.Location = New-Object System.Drawing.Point(10, 185)
$diskGroup.Size = New-Object System.Drawing.Size(330, 130)
$form.Controls.Add($diskGroup)

# Disk info text
$diskInfoText = New-Object System.Windows.Forms.Label
$diskInfoText.Font = $normalFont
$diskInfoText.Location = New-Object System.Drawing.Point(10, 20)
$diskInfoText.Size = New-Object System.Drawing.Size(310, 100)
$diskGroup.Controls.Add($diskInfoText)

# Size selection group
$sizeGroup = New-Object System.Windows.Forms.GroupBox
$sizeGroup.Text = "Linux Partition Size"
$sizeGroup.Font = $normalFont
$sizeGroup.Location = New-Object System.Drawing.Point(360, 185)
$sizeGroup.Size = New-Object System.Drawing.Size(330, 130)
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
$progressBar.Location = New-Object System.Drawing.Point(10, 325)
$progressBar.Size = New-Object System.Drawing.Size(680, 25)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

# Log group
$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = "Installation Log"
$logGroup.Font = $normalFont
$logGroup.Location = New-Object System.Drawing.Point(10, 360)
$logGroup.Size = New-Object System.Drawing.Size(680, 250)
$form.Controls.Add($logGroup)

# Log text box
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(10, 20)
$logBox.Size = New-Object System.Drawing.Size(660, 220)
$logGroup.Controls.Add($logBox)

# Delete ISO checkbox
$deleteIsoCheck = New-Object System.Windows.Forms.CheckBox
$deleteIsoCheck.Text = "Delete ISO file after installation"
$deleteIsoCheck.Font = $normalFont
$deleteIsoCheck.Location = New-Object System.Drawing.Point(10, 620)
$deleteIsoCheck.Size = New-Object System.Drawing.Size(300, 25)
$form.Controls.Add($deleteIsoCheck)

# Auto-restart checkbox
$autoRestartCheck = New-Object System.Windows.Forms.CheckBox
$autoRestartCheck.Text = "Automatically restart and configure UEFI boot"
$autoRestartCheck.Font = $normalFont
$autoRestartCheck.Location = New-Object System.Drawing.Point(10, 645)
$autoRestartCheck.Size = New-Object System.Drawing.Size(300, 25)
$autoRestartCheck.Checked = $true
$form.Controls.Add($autoRestartCheck)

# Start button
$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start Installation"
$startButton.Font = $boldFont
$startButton.Location = New-Object System.Drawing.Point(400, 640)
$startButton.Size = New-Object System.Drawing.Size(140, 35)
$startButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$startButton.ForeColor = [System.Drawing.Color]::White
$startButton.FlatStyle = "Flat"
$form.Controls.Add($startButton)

# Exit button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Font = $normalFont
$exitButton.Location = New-Object System.Drawing.Point(550, 640)
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
        $diskInfoText.Text = "Error retrieving disk information"
    }
}

function Create-BootConfigScript {
    param(
        [string]$VolumeLabelPattern,
        [string]$DistroName
    )
    
    $bootConfigScript = @'
# Set-UEFIDefaultBoot.ps1
# This script finds a firmware boot entry with description "UEFI OS" and sets it as default
# FIXED: Only runs once by checking/creating a marker file

# Check if this script has already run
$markerFile = "$env:ProgramData\LinuxBootConfig\boot_configured.marker"
if (Test-Path $markerFile) {
    Write-Host "Boot configuration has already been completed. Exiting..." -ForegroundColor Green
    
    # Clean up the scheduled task and RunOnce entry
    try {
        Unregister-ScheduledTask -TaskName "ConfigureLinuxBoot" -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
    
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ConfigureLinuxBoot" -ErrorAction SilentlyContinue
    } catch {}
    
    exit 0
}

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator. Exiting..." -ForegroundColor Red
    exit 1
}

Write-Host "Searching for UEFI OS boot entry..." -ForegroundColor Yellow

# Get all firmware entries
$bcdeditOutput = cmd /c "bcdedit /enum firmware"
$lines = $bcdeditOutput -split "`n"

$foundEntry = $false
$currentIdentifier = ""
$uefiOSIdentifier = ""

# Parse the output to find the UEFI OS entry
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    
    # Check if this is an identifier line
    if ($line -match "^identifier\s+(.+)$") {
        $currentIdentifier = $matches[1].Trim()
    }
    
    # Check if this is the description we're looking for
    if ($line -match "^description\s+UEFI OS\s*$") {
        $uefiOSIdentifier = $currentIdentifier
        $foundEntry = $true
        Write-Host "Found UEFI OS entry with identifier: $uefiOSIdentifier" -ForegroundColor Green
        break
    }
}

if (-not $foundEntry) {
    Write-Host "No firmware boot entry with description 'UEFI OS' was found." -ForegroundColor Red
    
    # Create marker file anyway to prevent re-runs
    $markerDir = Split-Path -Path $markerFile -Parent
    if (-not (Test-Path $markerDir)) {
        New-Item -Path $markerDir -ItemType Directory -Force | Out-Null
    }
    "Boot configuration attempted but no UEFI OS entry found - $(Get-Date)" | Out-File -FilePath $markerFile -Force
    
    # Clean up
    try {
        Unregister-ScheduledTask -TaskName "ConfigureLinuxBoot" -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
    
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ConfigureLinuxBoot" -ErrorAction SilentlyContinue
    } catch {}
    
    exit 1
}

# Get current display order
Write-Host "`nGetting current firmware display order..." -ForegroundColor Yellow
$currentOrder = @()

foreach ($line in $lines) {
    if ($line -match "^displayorder\s+(.+)$") {
        $orderString = $matches[1].Trim()
        $currentOrder = $orderString -split '\s+' | Where-Object { $_ -ne "" }
        break
    }
}

Write-Host "Current display order: $($currentOrder -join ', ')" -ForegroundColor Cyan

# Create new display order with UEFI OS first
$newOrder = @($uefiOSIdentifier)

# Add other entries (excluding the UEFI OS if it was already in the list)
foreach ($entry in $currentOrder) {
    if ($entry -ne $uefiOSIdentifier) {
        $newOrder += $entry
    }
}

Write-Host "`nNew display order will be: $($newOrder -join ', ')" -ForegroundColor Cyan

# Set the new display order
Write-Host "`nSetting new firmware display order..." -ForegroundColor Yellow

$orderString = $newOrder -join ' '
$command = "bcdedit /set `"{fwbootmgr}`" displayorder $orderString"

Write-Host "Executing: $command" -ForegroundColor Gray

$result = cmd /c $command 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nSuccess! UEFI OS has been set as the default boot entry." -ForegroundColor Green
    
    # Verify the change
    Write-Host "`nVerifying the change..." -ForegroundColor Yellow
    $verifyOutput = cmd /c "bcdedit /enum firmware" | Select-String -Pattern "displayorder" -Context 0,1
    Write-Host $verifyOutput -ForegroundColor Cyan
    
    # Create marker file to indicate successful completion
    $markerDir = Split-Path -Path $markerFile -Parent
    if (-not (Test-Path $markerDir)) {
        New-Item -Path $markerDir -ItemType Directory -Force | Out-Null
    }
    "Boot configuration completed successfully - $(Get-Date)" | Out-File -FilePath $markerFile -Force
    
} else {
    Write-Host "`nError: Failed to set the display order." -ForegroundColor Red
    Write-Host "Error details: $result" -ForegroundColor Red
    
    # Create marker file anyway to prevent re-runs
    $markerDir = Split-Path -Path $markerFile -Parent
    if (-not (Test-Path $markerDir)) {
        New-Item -Path $markerDir -ItemType Directory -Force | Out-Null
    }
    "Boot configuration failed - $(Get-Date)" | Out-File -FilePath $markerFile -Force
    
    # Clean up
    try {
        Unregister-ScheduledTask -TaskName "ConfigureLinuxBoot" -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
    
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ConfigureLinuxBoot" -ErrorAction SilentlyContinue
    } catch {}
    
    exit 1
}

# Clean up the scheduled task and RunOnce entry after successful execution
Write-Host "`nCleaning up auto-run entries..." -ForegroundColor Yellow

try {
    Unregister-ScheduledTask -TaskName "ConfigureLinuxBoot" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Scheduled task removed successfully" -ForegroundColor Green
} catch {
    Write-Host "Could not remove scheduled task: $_" -ForegroundColor Yellow
}

try {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ConfigureLinuxBoot" -ErrorAction SilentlyContinue
    Write-Host "RunOnce registry entry removed successfully" -ForegroundColor Green
} catch {
    Write-Host "Could not remove RunOnce entry: $_" -ForegroundColor Yellow
}

Write-Host "`nScript completed successfully!" -ForegroundColor Green
Write-Host "The system will now restart to boot into Linux..." -ForegroundColor Cyan

Start-Sleep -Seconds 5

Restart-Computer -Force

'@
    
    return $bootConfigScript
}

function Setup-AutoRunScript {
    param(
        [string]$ScriptContent,
        [string]$VolumeLabelPattern,
        [string]$DistroName
    )
    
    try {
        # Save the boot configuration script
        $scriptPath = "$env:ProgramData\LinuxBootConfig\configure_boot.ps1"
        $scriptDir = Split-Path -Path $scriptPath -Parent
        
        if (-not (Test-Path $scriptDir)) {
            New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
        }
        
        $ScriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -Force
        Log-Message "Boot configuration script saved to: $scriptPath"
        
        # Create a scheduled task to run once at next logon
        $taskName = "ConfigureLinuxBoot"
        
        # Remove existing task if present
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        } catch {}
        
        # Create the scheduled task
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -VolumeLabelPattern `"$VolumeLabelPattern`" -DistroName `"$DistroName`""
        
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME `
            -LogonType Interactive `
            -RunLevel Highest
        
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        
        Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
        
        Log-Message "Scheduled task created: $taskName"
        
        # Also create a RunOnce registry entry as backup
        $runOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        $runOnceCommand = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -VolumeLabelPattern `"$VolumeLabelPattern`" -DistroName `"$DistroName`""
        
        Set-ItemProperty -Path $runOncePath -Name "ConfigureLinuxBoot" -Value $runOnceCommand -Force
        Log-Message "RunOnce registry entry created"
        
        return $true
    }
    catch {
        Log-Message "Error setting up auto-run script: $_" -Error
        return $false
    }
}

function Verify-ISOChecksum {
    param(
        [string]$FilePath,
        [string]$Distribution
    )
    
    Log-Message "Verifying ISO checksum..."
    Set-Status "Verifying ISO integrity..."
    
    try {
        # Get expected checksum
        $expectedHash = $script:Checksums[$Distribution]
        if (-not $expectedHash) {
            Log-Message "Warning: No checksum available for $Distribution" -Error
            return $true  # Continue anyway
        }
        
        Log-Message "Expected SHA256: $expectedHash"
        
        # Calculate actual checksum
        Log-Message "Calculating SHA256 checksum (this may take a minute)..."
        $actualHash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop
        
        Log-Message "Actual SHA256: $($actualHash.Hash)"
        
        # Compare checksums (case-insensitive)
        if ($actualHash.Hash -eq $expectedHash) {
            Log-Message "[PASS] Checksum verification PASSED - ISO is authentic!"
            return $true
        } else {
            Log-Message "[FAIL] Checksum verification FAILED - ISO may be corrupted or tampered!" -Error
            
            $response = [System.Windows.Forms.MessageBox]::Show(
                "The ISO file checksum does not match the official checksum!`n`n" +
                "Expected: $expectedHash`n" +
                "Actual: $($actualHash.Hash)`n`n" +
                "This could mean the file is corrupted or has been tampered with.`n" +
                "Do you want to delete it and re-download?",
                "Checksum Verification Failed",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            
            if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Remove-Item $FilePath -Force
                    Log-Message "Corrupted ISO deleted"
                    return $false
                } catch {
                    Log-Message "Error deleting ISO: $_" -Error
                }
            }
            
            return $false
        }
    }
    catch {
        Log-Message "Error calculating checksum: $_" -Error
        
        # If checksum calculation fails, ask user what to do
        $response = [System.Windows.Forms.MessageBox]::Show(
            "Unable to verify the ISO checksum. Error: $_`n`n" +
            "Do you want to continue anyway?",
            "Checksum Verification Error",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        return ($response -eq [System.Windows.Forms.DialogResult]::Yes)
    }
}

function Download-LinuxISO {
    param(
        [string]$Destination,
        [string]$Distribution
    )
    
    # Select mirrors based on distribution
    if ($Distribution -eq "Kubuntu") {
        $mirrors = $script:KubuntuMirrors
        $isoName = "Kubuntu 25.04"
        $expectedSize = "approximately 4.8 GB"
    } else {
        $mirrors = $script:MintMirrors
        $isoName = "Linux Mint 22.1"
        $expectedSize = "approximately 2.9 GB"
    }
    
    Log-Message "Downloading $isoName ISO ($expectedSize)..."
    Log-Message "This may take a while depending on your internet speed..."
    
    foreach ($i in 0..($mirrors.Count - 1)) {
        $mirror = $mirrors[$i]
        Log-Message "Trying mirror $($i + 1)/$($mirrors.Count): $($mirror.Split('/')[2])"
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
                
                # Verify checksum
                if (-not (Verify-ISOChecksum -FilePath $Destination -Distribution $Distribution)) {
                    Log-Message "Checksum verification failed, trying next mirror..." -Error
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
            
            if ($i -lt $mirrors.Count - 1) {
                Log-Message "Trying next mirror..."
            }
        }
    }
    
    # If all mirrors fail, provide manual download option
    Log-Message "All automatic download attempts failed" -Error
    
    $downloadUrl = if ($Distribution -eq "Kubuntu") {
        "https://kubuntu.org/getkubuntu/"
    } else {
        "https://linuxmint.com/download.php"
    }
    
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
        Start-Process $downloadUrl
        Log-Message "Please download $isoName and save it as:"
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
    $autoRestartCheck.Enabled = $false
    $kubuntuRadio.Enabled = $false
    $mintRadio.Enabled = $false
    $customRadio.Enabled = $false
    $browseButton.Enabled = $false
    
    try {
        # Get selected distribution and ISO path
        if ($customRadio.Checked) {
            if (-not $script:CustomIsoPath -or -not (Test-Path $script:CustomIsoPath)) {
                Log-Message "Error: Please select a valid ISO file!" -Error
                return
            }
            $script:SelectedDistro = "Custom"
            $script:IsoPath = $script:CustomIsoPath
            
            # For custom ISOs, don't delete by default unless explicitly checked
            if (-not $deleteIsoCheck.Checked) {
                $deleteIsoCheck.Checked = $false
            }
        } else {
            $script:SelectedDistro = if ($kubuntuRadio.Checked) { "Kubuntu" } else { "Mint" }
            $script:IsoPath = if ($script:SelectedDistro -eq "Kubuntu") {
                "$env:TEMP\kubuntu-25.04.iso"
            } else {
                "$env:TEMP\linuxmint-22.1.iso"
            }
        }
        
        Log-Message "Selected distribution: $script:SelectedDistro"
        if ($script:SelectedDistro -eq "Custom") {
            Log-Message "Using custom ISO: $script:IsoPath"
            $isoInfo = Get-Item $script:IsoPath
            Log-Message "ISO file size: $([math]::Round($isoInfo.Length / 1GB, 2)) GB"
        }
        
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
        
        # Download ISO if needed (only for Kubuntu/Mint)
        if ($script:SelectedDistro -ne "Custom") {
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
                        
                        Set-Status "Re-downloading $script:SelectedDistro ISO..."
                        if (-not (Download-LinuxISO -Destination $script:IsoPath -Distribution $script:SelectedDistro)) {
                            Log-Message "Failed to download $script:SelectedDistro ISO!" -Error
                            return
                        }
                    } else {
                        # Verify checksum of existing ISO
                        if (-not (Verify-ISOChecksum -FilePath $script:IsoPath -Distribution $script:SelectedDistro)) {
                            Log-Message "Existing ISO failed checksum verification" -Error
                            
                            Set-Status "Re-downloading $script:SelectedDistro ISO..."
                            if (-not (Download-LinuxISO -Destination $script:IsoPath -Distribution $script:SelectedDistro)) {
                                Log-Message "Failed to download $script:SelectedDistro ISO!" -Error
                                return
                            }
                        } else {
                            # Try to verify the ISO is valid by mounting
                            try {
                                # Test if we can get disk image info
                                $testMount = Get-DiskImage -ImagePath $script:IsoPath -ErrorAction Stop
                                Log-Message "ISO mount test passed"
                            }
                            catch {
                                Log-Message "Existing ISO appears corrupted (mount test failed)" -Error
                                Log-Message "Error: $_" -Error
                                
                                $response = [System.Windows.Forms.MessageBox]::Show(
                                    "The existing ISO file appears to be corrupted. Would you like to re-download it?",
                                    "Corrupted ISO",
                                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                                    [System.Windows.Forms.MessageBoxIcon]::Warning
                                )
                                
                                if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
                                    Remove-Item $script:IsoPath -Force
                                    Set-Status "Re-downloading $script:SelectedDistro ISO..."
                                    if (-not (Download-LinuxISO -Destination $script:IsoPath -Distribution $script:SelectedDistro)) {
                                        Log-Message "Failed to download $script:SelectedDistro ISO!" -Error
                                        return
                                    }
                                } else {
                                    Log-Message "Installation cancelled by user" -Error
                                    return
                                }
                            }
                        }
                    }
                }
                catch {
                    Log-Message "Error checking existing ISO: $_" -Error
                    return
                }
            } else {
                Set-Status "Downloading $script:SelectedDistro ISO..."
                if (-not (Download-LinuxISO -Destination $script:IsoPath -Distribution $script:SelectedDistro)) {
                    Log-Message "Failed to download $script:SelectedDistro ISO!" -Error
                    return
                }
            }
        }
        
        # Shrink C: partition by the total amount needed
        Set-Status "Shrinking C: partition..."
        Log-Message "Shrinking C: partition by $totalNeededGB GB total..."
        $bootSizeGB = $script:MinPartitionSizeGB
        Log-Message "This will create space for Linux: $linuxSizeGB GB and boot partition: $bootSizeGB GB..."
        
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
        
        # Create boot partition at the end of the unallocated space
        Set-Status "Creating boot partition..."
        Log-Message "Creating $script:MinPartitionSizeGB GB boot partition at end of disk..."
        
        try {
            # Refresh disk information
            Start-Sleep -Seconds 2
            $disk = Get-Disk -Number $script:CDriveInfo.DiskNumber
            $partitions = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber | Sort-Object Offset
            
            # Get the C: partition info
            $cPartition = Get-Partition -DriveLetter C
            $cPartitionEnd = $cPartition.Offset + $cPartition.Size
            
            # Find all partitions after C:
            $partitionsAfterC = $partitions | Where-Object { $_.Offset -ge $cPartitionEnd }
            
            if ($partitionsAfterC) {
                Log-Message "Found $($partitionsAfterC.Count) partition(s) after C: drive"
                foreach ($part in $partitionsAfterC) {
                    $sizeGB = [math]::Round($part.Size / 1GB, 2)
                    $offsetGB = [math]::Round($part.Offset / 1GB, 2)
                    $type = if ($part.Type -eq "Recovery") { "Recovery" } 
                           elseif ($part.IsSystem) { "System" }
                           elseif ($part.GptType -match "de94bba4") { "Recovery" }
                           else { "Unknown" }
                    Log-Message "- Partition at $offsetGB GB: $sizeGB GB ($type)"
                }
                
                # Find the first partition after C: (usually recovery)
                $firstPartitionAfterC = $partitionsAfterC | Sort-Object Offset | Select-Object -First 1
                $recoveryOffset = $firstPartitionAfterC.Offset
                $recoveryOffsetGB = [math]::Round($recoveryOffset / 1GB, 2)
                
                # Calculate available space between C: and recovery partition
                $availableSpace = $recoveryOffset - $cPartitionEnd
                $availableSpaceGB = [math]::Round($availableSpace / 1GB, 2)
                
                Log-Message "Available space between C: and recovery partition: $availableSpaceGB GB"
                
                # Calculate where to place boot partition (just before recovery)
                $bootPartitionSize = [int64]($script:MinPartitionSizeGB * 1GB)
                
                # Account for disk alignment (Windows typically uses 1MB alignment)
                $alignmentSize = [int64](1MB)
                
                # Calculate the exact position
                # Boot partition should end where recovery begins (with buffer)
                $bufferSize = [int64](16MB)  # 16MB buffer for safety and alignment
                $bootPartitionEndOffset = $recoveryOffset - $bufferSize
                $bootPartitionOffset = $bootPartitionEndOffset - $bootPartitionSize
                
                # Ensure offset is aligned to 1MB boundary
                $bootPartitionOffset = [int64]([Math]::Floor($bootPartitionOffset / $alignmentSize)) * $alignmentSize
                
                # Verify we have enough space
                if ($bootPartitionOffset -lt ($cPartitionEnd + $alignmentSize)) {
                    throw "Not enough space between C: and recovery partition"
                }
                
                # Calculate actual Linux space
                $linuxSpace = $bootPartitionOffset - $cPartitionEnd
                $linuxSpaceGB = [math]::Round($linuxSpace / 1GB, 2)
                
                Log-Message "Unallocated space starts at: $([math]::Round($cPartitionEnd / 1GB, 2)) GB"
                Log-Message "Boot partition will start at: $([math]::Round($bootPartitionOffset / 1GB, 2)) GB"
                Log-Message "Recovery partition starts at: $recoveryOffsetGB GB"
                Log-Message "Linux will have $linuxSpaceGB GB of unallocated space"
                
            } else {
                Log-Message "No partitions found after C: drive"
                # Place boot partition at end of unallocated space as originally planned
                $bootPartitionOffset = [int64]($cPartitionEnd + ($linuxSizeGB * 1GB))
            }
            
            # Create boot partition using diskpart with specific offset
            Log-Message "Creating boot partition..."
            
            # Use 64-bit integer for MB conversion to avoid overflow
            $offsetMB = [int64]([Math]::Floor($bootPartitionOffset / 1MB))
            $sizeMB = [int64]($script:MinPartitionSizeGB * 1024)
            
            # Validate offset before attempting
            if ($offsetMB -lt 0 -or $bootPartitionOffset -gt $disk.Size) {
                throw "Invalid offset calculated: $offsetMB MB (from $bootPartitionOffset bytes)"
            }
            
            Log-Message "Attempting to create partition at offset: $([math]::Round($bootPartitionOffset / 1GB, 2)) GB - $offsetMB MB"
            
            # First attempt: Try with PowerShell cmdlet using offset
            $partitionCreated = $false
            $newPartition = $null
            
            try {
                Log-Message "Attempting PowerShell method with specific offset..."
                $newPartition = New-Partition -DiskNumber $script:CDriveInfo.DiskNumber `
                    -Offset $bootPartitionOffset `
                    -Size $bootPartitionSize `
                    -AssignDriveLetter `
                    -ErrorAction Stop
                    
                $partitionCreated = $true
                $driveLetter = $newPartition.DriveLetter
                Log-Message "Success! Partition created using PowerShell method"
            }
            catch {
                Log-Message "PowerShell method failed: $_"
                Log-Message "Trying diskpart method..."
                
                # Try multiple attempts with different offsets if needed
                $attempts = @(
                    @{Offset = $offsetMB; Description = "Calculated position (just before recovery)"},
                    @{Offset = [int64]($offsetMB - 1024); Description = "1GB before calculated position"},
                    @{Offset = [int64]($offsetMB - 2048); Description = "2GB before calculated position"},
                    @{Offset = [int64]($offsetMB - 5120); Description = "5GB before calculated position"}
                )
                
                # Filter out negative offsets
                $attempts = $attempts | Where-Object { $_.Offset -gt 0 }
                
                foreach ($attempt in $attempts) {
                    Log-Message "Attempt: $($attempt.Description)"
                    Log-Message "Trying offset: $([math]::Round($attempt.Offset * 1MB / 1GB, 2)) GB"
                    
                    $diskpartScript = @"
select disk $($script:CDriveInfo.DiskNumber)
create partition primary offset=$($attempt.Offset) size=$sizeMB
assign
exit
"@
                    $scriptPath = "$env:TEMP\create_boot_partition.txt"
                    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
                    
                    $result = & diskpart /s $scriptPath 2>&1
                    Remove-Item $scriptPath -Force
                    
                    $resultString = $result -join "`n"
                    
                    if ($resultString -match "successfully created" -or $resultString -match "DiskPart successfully created") {
                        Log-Message "Success! Boot partition created at offset $([math]::Round($attempt.Offset * 1MB / 1GB, 2)) GB"
                        $partitionCreated = $true
                        $successfulOffset = [int64]($attempt.Offset) * 1MB
                        break
                    } else {
                        if ($resultString -match "not enough usable space") {
                            Log-Message "Not enough space at this offset, trying next position..."
                        } else {
                            Log-Message "Failed with error: $($resultString | Select-String -Pattern 'error' -SimpleMatch)"
                        }
                    }
                }
            }
            
            # If offset-based creation failed, try the filler partition workaround
            if (-not $partitionCreated) {
                Log-Message "Offset-based creation failed. Trying alternative approach..."
                
                # Get current partitions after shrinking
                $currentPartitions = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber | Sort-Object Offset
                $cPartition = $currentPartitions | Where-Object { $_.DriveLetter -eq 'C' }
                $cEndOffset = $cPartition.Offset + $cPartition.Size
                
                # Find the recovery partition
                $recoveryPartition = $currentPartitions | Where-Object { 
                    $_.Type -eq "Recovery" -or $_.GptType -match "de94bba4"
                } | Sort-Object Offset | Select-Object -First 1
                
                if ($recoveryPartition) {
                    $gapSize = $recoveryPartition.Offset - $cEndOffset
                    $gapSizeGB = [math]::Round($gapSize / 1GB, 2)
                    Log-Message "Gap between C: and Recovery: $gapSizeGB GB"
                    
                    # Try creating a large partition to fill most of the gap
                    # This might force Windows to place the boot partition at the end
                    $fillerSize = [int64]($gapSize - ($script:MinPartitionSizeGB * 1GB) - (1GB))  # Leave space for boot + buffer
                    $fillerSizeGB = [math]::Round($fillerSize / 1GB, 2)
                    
                    if ($fillerSize -gt 0) {
                        Log-Message "Attempting workaround: Creating filler partition of $fillerSizeGB GB"
                        
                        try {
                            # Create large partition (no drive letter)
                            $fillerPartition = New-Partition -DiskNumber $script:CDriveInfo.DiskNumber `
                                -Size $fillerSize `
                                -ErrorAction Stop
                            
                            Log-Message "Filler partition created. Now creating boot partition..."
                            
                            # Now create boot partition (should go at the end)
                            $bootPartition = New-Partition -DiskNumber $script:CDriveInfo.DiskNumber `
                                -Size ($script:MinPartitionSizeGB * 1GB) `
                                -AssignDriveLetter `
                                -ErrorAction Stop
                            
                            # Delete the filler partition
                            Log-Message "Removing filler partition..."
                            Remove-Partition -DiskNumber $script:CDriveInfo.DiskNumber `
                                -PartitionNumber $fillerPartition.PartitionNumber `
                                -Confirm:$false `
                                -ErrorAction Stop
                            
                            Log-Message "Filler partition removed. Boot partition should now be at end."
                            $partitionCreated = $true
                            $newPartition = $bootPartition
                            
                            # Get the drive letter
                            $driveLetter = $bootPartition.DriveLetter
                            
                            if (-not $driveLetter) {
                                # Wait and retry
                                Start-Sleep -Seconds 3
                                $bootPartition = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber -PartitionNumber $bootPartition.PartitionNumber
                                $driveLetter = $bootPartition.DriveLetter
                            }
                            
                        }
                        catch {
                            Log-Message "Workaround failed: $_" -Error
                        }
                    }
                }
            }
            
            # Final fallback: Create partition without specific offset
            if (-not $partitionCreated) {
                Log-Message "All offset methods failed. Creating partition without specific offset..."
                try {
                    $newPartition = New-Partition -DiskNumber $script:CDriveInfo.DiskNumber `
                        -Size ($script:MinPartitionSizeGB * 1GB) `
                        -AssignDriveLetter `
                        -ErrorAction Stop
                    
                    $driveLetter = $newPartition.DriveLetter
                    $partitionCreated = $true
                    Log-Message "Boot partition created using standard method"
                }
                catch {
                    throw "All partition creation methods failed: $_"
                }
            }
            
            if ($partitionCreated -and -not $driveLetter) {
                # Wait for the partition to be recognized
                Start-Sleep -Seconds 3
                
                # Find the new partition - look for one around 7GB in size
                $targetSize = [int64]($script:MinPartitionSizeGB * 1GB)
                $tolerance = [int64](100MB)  # 100MB tolerance
                
                $newPartitions = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber | 
                    Where-Object { [Math]::Abs($_.Size - $targetSize) -lt $tolerance }
                
                # Get the one with the highest offset (should be our new one)
                $bootPartition = $newPartitions | Sort-Object Offset -Descending | Select-Object -First 1
                
                if ($bootPartition) {
                    $driveLetter = $bootPartition.DriveLetter
                    
                    if (-not $driveLetter) {
                        # Try to assign manually
                        $bootPartition | Add-PartitionAccessPath -AssignDriveLetter
                        Start-Sleep -Seconds 2
                        $bootPartition = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber -PartitionNumber $bootPartition.PartitionNumber
                        $driveLetter = $bootPartition.DriveLetter
                    }
                } else {
                    throw "Cannot find newly created boot partition"
                }
            }
            
            if (-not $driveLetter) {
                throw "Failed to get drive letter for boot partition"
            }
            
            Log-Message "Formatting boot partition as FAT32..."
            
            # Set volume label based on distribution
            $volumeLabel = if ($script:SelectedDistro -eq "Custom") { 
                "LINUX_BOOT" 
            } elseif ($script:SelectedDistro -eq "Kubuntu") { 
                "KUBUNTU" 
            } else { 
                "LINUXMINT" 
            }
            
            # Format as FAT32
            Format-Volume -DriveLetter $driveLetter `
                -FileSystem FAT32 `
                -NewFileSystemLabel $volumeLabel `
                -Confirm:$false `
                -ErrorAction Stop
            
            Log-Message "Boot partition created and assigned to ${driveLetter}:"
            $script:NewDrive = "${driveLetter}:"
            
            # Store volume label for boot configuration
            $script:VolumeLabel = $volumeLabel
            
            # Verify and log final partition layout
            Log-Message ""
            Log-Message "=== Final Disk Layout ==="
            $finalPartitions = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber | Sort-Object Offset
            
            $previousEnd = [int64]0
            foreach ($part in $finalPartitions) {
                $sizeGB = [math]::Round($part.Size / 1GB, 2)
                $offsetGB = [math]::Round($part.Offset / 1GB, 2)
                $endGB = [math]::Round(($part.Offset + $part.Size) / 1GB, 2)
                
                # Check for gap before this partition
                if ($part.Offset -gt ($previousEnd + 1MB)) {
                    $gapSize = [math]::Round(($part.Offset - $previousEnd) / 1GB, 2)
                    if ($gapSize -gt 0.1) {  # Only show gaps larger than 100MB
                        Log-Message "[Unallocated: $gapSize GB]"
                    }
                }
                
                $label = if ($part.DriveLetter) { "Drive $($part.DriveLetter):" } 
                        elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") { "(Recovery)" }
                        elseif ($part.IsSystem) { "(System)" }
                        else { "(No letter)" }
                
                Log-Message "Partition $($part.PartitionNumber): $label - Size: $sizeGB GB - Location: $offsetGB-$endGB GB"
                
                $previousEnd = [int64]($part.Offset + $part.Size)
            }
            
            # Check for trailing unallocated space
            if ($disk.Size -gt ($previousEnd + 1MB)) {
                $trailingGap = [math]::Round(($disk.Size - $previousEnd) / 1GB, 2)
                if ($trailingGap -gt 0.1) {
                    Log-Message "[Unallocated: $trailingGap GB]"
                }
            }
            
            Log-Message ""
            Log-Message "Boot partition successfully created!"
            Log-Message "Linux can use the unallocated space for installation"
            
        }
        catch {
            Log-Message "Failed to create boot partition: $_" -Error
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
            
            # For custom ISOs, skip validation
            if ($script:SelectedDistro -ne "Custom") {
                # Verify mount by checking for expected files
                $validationFile = if ($script:SelectedDistro -eq "Kubuntu") { 
                    "$sourceDrive\casper\vmlinuz"
                } else { 
                    "$sourceDrive\casper\vmlinuz" 
                }
                
                if (-not (Test-Path $validationFile)) {
                    Log-Message "Warning: ISO might not be a valid $script:SelectedDistro image (missing expected files)" -Error
                    
                    $response = [System.Windows.Forms.MessageBox]::Show(
                        "The ISO doesn't appear to be a valid $script:SelectedDistro image. Continue anyway?",
                        "Invalid ISO",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    
                    if ($response -ne [System.Windows.Forms.DialogResult]::Yes) {
                        Dismount-DiskImage -ImagePath $script:IsoPath
                        return
                    }
                }
            } else {
                Log-Message "Custom ISO mounted. Skipping validation."
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
            
            if ($response -eq [System.Windows.Forms.DialogResult]::Yes -and $script:SelectedDistro -ne "Custom") {
                try {
                    Remove-Item $script:IsoPath -Force
                    Log-Message "Deleted corrupted ISO"
                    
                    Set-Status "Re-downloading $script:SelectedDistro ISO..."
                    if (Download-LinuxISO -Destination $script:IsoPath -Distribution $script:SelectedDistro) {
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
        $distroName = if ($script:SelectedDistro -eq "Custom") { "Linux" } else { $script:SelectedDistro }
        Log-Message "Copying $distroName files to $script:NewDrive..."
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
        
        # Setup auto-run script if enabled
        if ($autoRestartCheck.Checked) {
            Log-Message "Setting up automatic UEFI boot configuration..."
            
            # Create the boot configuration script
            $bootScript = Create-BootConfigScript -VolumeLabelPattern $script:VolumeLabel -DistroName $distroName
            
            # Setup the auto-run mechanism
            $setupSuccess = Setup-AutoRunScript -ScriptContent $bootScript -VolumeLabelPattern $script:VolumeLabel -DistroName $distroName
            
            if ($setupSuccess) {
                Log-Message "Auto-restart and boot configuration enabled"
                Log-Message "System will restart after completion and configure UEFI boot"
            } else {
                Log-Message "Warning: Could not setup auto-restart. Manual configuration required." -Error
            }
        }
        
        # Create boot instructions
        $instructions = @"
UEFI Boot Setup Instructions for $distroName
==========================================

Your $distroName bootable partition has been created successfully!

Disk Layout:
- Windows C: drive (shrunk)
- Unallocated space: $linuxSizeGB GB (for Linux installation)
- Boot Drive: $script:NewDrive (7 GB, FAT32)
- Disk Number: $($script:CDriveInfo.DiskNumber)

Important: The disk now has unallocated space that
the $distroName installer will automatically detect and use.

"@

        if ($autoRestartCheck.Checked) {
            $instructions += @"

AUTOMATIC BOOT CONFIGURATION ENABLED:
====================================
The system will automatically restart and configure UEFI boot.
After restart:
1. Windows will boot once more to configure UEFI settings
2. The system will then restart again and boot into $distroName
3. You can proceed with the installation

If automatic configuration fails, follow the manual steps below.

"@
        }

        $instructions += @"

MANUAL BOOT CONFIGURATION (if needed):
=====================================

To boot ${distroName}:

1. Restart your computer

2. Access UEFI/BIOS settings:
   - During startup, press the BIOS key (usually F2, F10, F12, DEL, or ESC)
   - The exact key depends on your motherboard manufacturer

3. In UEFI settings:
   - Look for "Boot" or "Boot Order" section
   - Find the $distroName entry (may appear as "UEFI: $script:NewDrive $($script:VolumeLabel)")
   - Set it as the first boot priority
   - OR use the one-time boot menu (usually F12) to select it

4. Important Settings:
   - Disable Secure Boot (if enabled)
   - Ensure UEFI mode is enabled (not Legacy/CSM)
   - Save changes and exit

5. The system should now boot into $distroName Live environment

6. During $distroName installation:
   - The installer will automatically find the $linuxSizeGB GB unallocated space
   - Choose "Install alongside Windows" or use manual partitioning
   - The installer will create the necessary Linux partitions in that space
   - The bootloader will be configured automatically

Note: The Windows Boot Manager entry was NOT modified to prevent boot issues.
      Use the UEFI boot menu to select between Windows and $distroName.

Troubleshooting:
- If you don't see the $distroName option, try disabling Fast Boot
- Some systems require you to manually add a boot entry pointing to:
  \EFI\BOOT\BOOTx64.EFI on the $($script:VolumeLabel) partition
- If the installer doesn't see the unallocated space, use the manual
  partitioning option and create your partitions in the free space
"@
        
        # Save instructions
        $instructions | Out-File -FilePath "$script:NewDrive\UEFI_BOOT_INSTRUCTIONS.txt" -Encoding UTF8
        $instructions | Out-File -FilePath "$env:USERPROFILE\Desktop\${distroName}_Boot_Instructions.txt" -Encoding UTF8
        
        # Success
        Log-Message "====================================="
        Log-Message "Installation Complete!"
        Log-Message "====================================="
        Log-Message "$distroName boot partition created at drive $script:NewDrive"
        if ($script:SelectedDistro -eq "Custom") {
            Log-Message "ISO used: $(Split-Path -Leaf $script:CustomIsoPath)"
        }
        Log-Message ""
        Log-Message "*** DISK LAYOUT ***"
        $finalPartitions = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber | Sort-Object Offset
        foreach ($part in $finalPartitions) {
            $sizeGB = [math]::Round($part.Size / 1GB, 2)
            $label = if ($part.DriveLetter) { "Drive $($part.DriveLetter)" } 
                    elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") { "Recovery" }
                    elseif ($part.IsSystem) { "System" }
                    else { "No letter" }
            Log-Message "- ${label}: $sizeGB GB"
        }
        Log-Message ""
        Log-Message "The unallocated space is ready for $distroName installation."
        Log-Message "The installer will automatically detect and use this space."
        Log-Message ""
        
        if ($autoRestartCheck.Checked) {
            Log-Message "*** AUTOMATIC RESTART ENABLED ***"
            Log-Message "The system will restart in 30 seconds!"
            Log-Message "After restart:"
            Log-Message "1. Windows will boot once more to configure UEFI"
            Log-Message "2. Then it will restart again into $distroName"
            Log-Message ""
        } else {
            Log-Message "*** IMPORTANT BOOT INSTRUCTIONS ***"
            Log-Message "The Windows Boot Manager was NOT modified."
            Log-Message "To boot $distroName, use the UEFI boot menu:"
            Log-Message "1. Restart your computer"
            Log-Message "2. Press F2, F10, F12, DEL, or ESC during startup"
            Log-Message "3. Select the $distroName entry"
            Log-Message "4. Make sure Secure Boot is disabled"
            Log-Message ""
        }
        
        Log-Message "Instructions saved to:"
        Log-Message "- $script:NewDrive\UEFI_BOOT_INSTRUCTIONS.txt"
        Log-Message "- Desktop\${distroName}_Boot_Instructions.txt"
        
        Set-Status "Installation complete!"
        
        # Delete ISO if requested
        if ($deleteIsoCheck.Checked -and $script:SelectedDistro -ne "Custom") {
            try {
                Remove-Item $script:IsoPath -Force
                Log-Message "ISO file deleted."
            }
            catch {
                Log-Message "Could not delete ISO file."
            }
        }
        
        # Auto-restart if enabled
        if ($autoRestartCheck.Checked) {
            Log-Message ""
            Log-Message "Preparing for automatic restart..."
            
            # Show countdown dialog
            $countdownForm = New-Object System.Windows.Forms.Form
            $countdownForm.Text = "System Restart"
            $countdownForm.Size = New-Object System.Drawing.Size(400, 200)
            $countdownForm.StartPosition = "CenterScreen"
            $countdownForm.FormBorderStyle = "FixedDialog"
            $countdownForm.MaximizeBox = $false
            $countdownForm.MinimizeBox = $false
            
            $countdownLabel = New-Object System.Windows.Forms.Label
            $countdownLabel.Text = "System will restart in 30 seconds...`n`nAfter restart, Windows will boot once more to configure UEFI settings, then restart again into $distroName."
            $countdownLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $countdownLabel.Location = New-Object System.Drawing.Point(20, 20)
            $countdownLabel.Size = New-Object System.Drawing.Size(360, 80)
            $countdownLabel.TextAlign = "MiddleCenter"
            $countdownForm.Controls.Add($countdownLabel)
            
            $cancelButton = New-Object System.Windows.Forms.Button
            $cancelButton.Text = "Cancel Restart"
            $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $cancelButton.Location = New-Object System.Drawing.Point(125, 110)
            $cancelButton.Size = New-Object System.Drawing.Size(150, 35)
            $countdownForm.Controls.Add($cancelButton)
            
            $script:CancelRestart = $false
            $cancelButton.Add_Click({
                $script:CancelRestart = $true
                $countdownForm.Close()
            })
            
            # Timer for countdown
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 1000
            $script:CountdownSeconds = 30
            
            $timer.Add_Tick({
                $script:CountdownSeconds--
                $countdownLabel.Text = "System will restart in $script:CountdownSeconds seconds...`n`nAfter restart, Windows will boot once more to configure UEFI settings, then restart again into $distroName."
                
                if ($script:CountdownSeconds -le 0) {
                    $timer.Stop()
                    $countdownForm.Close()
                }
            })
            
            $timer.Start()
            $countdownForm.ShowDialog()
            $timer.Stop()
            
            if (-not $script:CancelRestart) {
                Log-Message "Restarting system..."
                Start-Sleep -Seconds 2
                Restart-Computer -Force
            } else {
                Log-Message "Restart cancelled by user"
                Log-Message "You can restart manually when ready"
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
        $autoRestartCheck.Enabled = $true
        $kubuntuRadio.Enabled = $true
        $mintRadio.Enabled = $true
        $customRadio.Enabled = $true
        if ($customRadio.Checked) {
            $browseButton.Enabled = $true
        }
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

# Radio button event handlers
$kubuntuRadio.Add_CheckedChanged({
    if ($kubuntuRadio.Checked) {
        $customIsoTextbox.Enabled = $false
        $browseButton.Enabled = $false
        $deleteIsoCheck.Checked = $false
    }
})

$mintRadio.Add_CheckedChanged({
    if ($mintRadio.Checked) {
        $customIsoTextbox.Enabled = $false
        $browseButton.Enabled = $false
        $deleteIsoCheck.Checked = $false
    }
})

$customRadio.Add_CheckedChanged({
    if ($customRadio.Checked) {
        $customIsoTextbox.Enabled = $true
        $browseButton.Enabled = $true
        $deleteIsoCheck.Checked = $false
    }
})

# Browse button event handler
$browseButton.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Select Linux ISO File"
    $openFileDialog.Filter = "ISO Files (*.iso)|*.iso|All Files (*.*)|*.*"
    $openFileDialog.FilterIndex = 1
    $openFileDialog.RestoreDirectory = $true
    
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:CustomIsoPath = $openFileDialog.FileName
        $customIsoTextbox.Text = $script:CustomIsoPath
        
        # Show file info
        $fileInfo = Get-Item $script:CustomIsoPath
        $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
        Log-Message "Selected ISO: $(Split-Path -Leaf $script:CustomIsoPath)"
        Log-Message "File size: $fileSizeGB GB"
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