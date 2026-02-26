# Linux Installer for Windows 11 UEFI Systems - Enhanced Edition with Auto-Restart
# PowerShell GUI Version - Fixed unit conversions for proper partition placement
# Run as Administrator: powershell -ExecutionPolicy Bypass -File linux_installer.ps1
# Distributions: Linux Mint 22.3 "Zena" (Cinnamon Edition), Ubuntu 24.04.4 LTS, Kubuntu 24.04.4 LTS, Debian Live 13.3.0 KDE, Fedora 43 KDE

#Requires -Version 5.1

# ─── Auto-elevate to Administrator ────────────────────────────────────────────
# If not running as admin, re-launch this script elevated via UAC prompt.
# The user sees the standard "Do you want to allow this app to make changes?"
# dialog, clicks Yes, and the script continues seamlessly in a new window.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`""
        ) -Verb RunAs
    } catch {
        Write-Host "ERROR: Administrator privileges are required to run ULLI." -ForegroundColor Red
        Write-Host "Please right-click the script and select 'Run as Administrator'."
        Read-Host "Press Enter to exit"
    }
    exit
}

# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Global variables
$script:MinPartitionSizeGB = 7
$script:MinLinuxSizeGB = 20
$script:MintMirrors = @(
    "https://mirrors.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso",
    "https://mirror.csclub.uwaterloo.ca/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso",
    "https://mirrors.seas.harvard.edu/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso",
    "https://mirror.arizona.edu/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso"
)

# Official SHA256 checksum for linuxmint-22.3-cinnamon-64bit.iso
$script:ExpectedChecksum = "a081ab202cfda17f6924128dbd2de8b63518ac0531bcfe3f1a1b88097c459bd4"
$script:IsoFilename = "linuxmint-22.3-cinnamon-64bit.iso"

# Ubuntu 24.04.4 LTS mirrors and checksum
$script:UbuntuMirrors = @(
    "https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-desktop-amd64.iso",
    "https://mirror.cs.uchicago.edu/ubuntu-releases/24.04.4/ubuntu-24.04.4-desktop-amd64.iso",
    "https://mirrors.mit.edu/ubuntu-releases/24.04.4/ubuntu-24.04.4-desktop-amd64.iso",
    "https://ubuntu.osuosl.org/ubuntu-releases/24.04.4/ubuntu-24.04.4-desktop-amd64.iso"
)
# Official SHA256 checksum for ubuntu-24.04.4-desktop-amd64.iso
$script:UbuntuChecksum = "3a4c9877b483ab46d7c3fbe165a0db275e1ae3cfe56a5657e5a47c2f99a99d1e"
$script:UbuntuIsoFilename = "ubuntu-24.04.4-desktop-amd64.iso"

# Kubuntu 24.04.4 LTS mirrors and checksum
$script:KubuntuMirrors = @(
    "https://cdimage.ubuntu.com/kubuntu/releases/24.04.4/release/kubuntu-24.04.4-desktop-amd64.iso",
    "https://mirror.netzwerge.de/ubuntu-dvd/kubuntu/releases/24.04/release/kubuntu-24.04.4-desktop-amd64.iso",
    "https://ftpmirror.your.org/pub/ubuntu/cdimage/kubuntu/releases/24.04/release/kubuntu-24.04.4-desktop-amd64.iso",
    "https://www.mirrorservice.org/sites/cdimage.ubuntu.com/cdimage/kubuntu/releases/24.04/release/kubuntu-24.04.4-desktop-amd64.iso"
)
# Official SHA256 checksum for kubuntu-24.04.4-desktop-amd64.iso
$script:KubuntuChecksum = "02cda2568cb96c090b0438a31a7d2e7b07357fde16217c215e7c3f45263bcc49"
$script:KubuntuIsoFilename = "kubuntu-24.04.4-desktop-amd64.iso"

# Debian Live 13.3.0 KDE mirrors and checksum
$script:DebianMirrors = @(
    "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.3.0-amd64-kde.iso",
    "https://mirrors.kernel.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.3.0-amd64-kde.iso",
    "https://mirror.csclub.uwaterloo.ca/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.3.0-amd64-kde.iso",
    "https://mirrors.mit.edu/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.3.0-amd64-kde.iso"
)
# Official SHA256 checksum for debian-live-13.3.0-amd64-kde.iso
$script:DebianChecksum = "6a162340bca02edf67e159c847cd605618a77d50bf82088ee514f83369e43b89"
$script:DebianIsoFilename = "debian-live-13.3.0-amd64-kde.iso"

# Fedora 43 KDE Plasma Desktop Live mirrors and checksum
$script:FedoraMirrors = @(
    "https://d2lzkl7pfhq30w.cloudfront.net/pub/fedora/linux/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso",
    "https://mirror.web-ster.com/fedora/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso",
    "https://forksystems.mm.fcix.net/fedora/linux/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso",
    "https://southfront.mm.fcix.net/fedora/linux/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso"
)
# Official SHA256 checksum for Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso
$script:FedoraChecksum = "181fe3e265fb5850c929f5afb7bdca91bb433b570ef39ece4a7076187435fdab"
$script:FedoraIsoFilename = "Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso"

$script:IsoPath = ""
$script:CustomIsoPath = ""
$script:IsRunning = $false

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "USB-less Linux Installer for Windows"
$form.Size = New-Object System.Drawing.Size(720, 770)
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
$headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
$headerLabel.Location = New-Object System.Drawing.Point(10, 10)
$headerLabel.Size = New-Object System.Drawing.Size(680, 30)
$headerLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($headerLabel)

# Sub-header label
$subHeaderLabel = New-Object System.Windows.Forms.Label
$subHeaderLabel.Text = "Mint 22.3, Ubuntu 24.04.4, Kubuntu 24.04.4, Debian 13.3.0, or Fedora 43  |  No USB required"
$subHeaderLabel.Font = $normalFont
$subHeaderLabel.ForeColor = [System.Drawing.Color]::DimGray
$subHeaderLabel.Location = New-Object System.Drawing.Point(10, 42)
$subHeaderLabel.Size = New-Object System.Drawing.Size(680, 18)
$subHeaderLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($subHeaderLabel)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready to install"
$statusLabel.Font = $normalFont
$statusLabel.Location = New-Object System.Drawing.Point(10, 62)
$statusLabel.Size = New-Object System.Drawing.Size(680, 20)
$statusLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($statusLabel)

# Progress bar (right underneath the status label)
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 84)
$progressBar.Size = New-Object System.Drawing.Size(680, 14)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

# ISO source group
$isoGroup = New-Object System.Windows.Forms.GroupBox
$isoGroup.Text = "Distribution"
$isoGroup.Font = $normalFont
$isoGroup.Location = New-Object System.Drawing.Point(10, 104)
$isoGroup.Size = New-Object System.Drawing.Size(680, 174)
$form.Controls.Add($isoGroup)

# Panel to isolate distro radio buttons
$distroPanel = New-Object System.Windows.Forms.Panel
$distroPanel.Location = New-Object System.Drawing.Point(10, 15)
$distroPanel.Size = New-Object System.Drawing.Size(650, 122)
$isoGroup.Controls.Add($distroPanel)

# Distro selection: Linux Mint radio button
$mintRadio = New-Object System.Windows.Forms.RadioButton
$mintRadio.Text = "Linux Mint 22.3 `"Zena`" - Cinnamon Edition (approx. 2.9 GB)"
$mintRadio.Font = $boldFont
$mintRadio.Location = New-Object System.Drawing.Point(0, 0)
$mintRadio.Size = New-Object System.Drawing.Size(640, 20)
$mintRadio.Checked = $true
$distroPanel.Controls.Add($mintRadio)

# Distro selection: Ubuntu 24.04.4 LTS radio button
$ubuntuRadio = New-Object System.Windows.Forms.RadioButton
$ubuntuRadio.Text = "Ubuntu 24.04.4 LTS - GNOME Edition (approx. 5.9 GB)"
$ubuntuRadio.Font = $boldFont
$ubuntuRadio.Location = New-Object System.Drawing.Point(0, 24)
$ubuntuRadio.Size = New-Object System.Drawing.Size(640, 20)
$distroPanel.Controls.Add($ubuntuRadio)

# Distro selection: Kubuntu 24.04.4 LTS radio button
$kubuntuRadio = New-Object System.Windows.Forms.RadioButton
$kubuntuRadio.Text = "Kubuntu 24.04.4 LTS - KDE Plasma 5 Edition (approx. 4.2 GB)"
$kubuntuRadio.Font = $boldFont
$kubuntuRadio.Location = New-Object System.Drawing.Point(0, 48)
$kubuntuRadio.Size = New-Object System.Drawing.Size(640, 20)
$distroPanel.Controls.Add($kubuntuRadio)

# Distro selection: Debian Live 13.3.0 KDE radio button
$debianRadio = New-Object System.Windows.Forms.RadioButton
$debianRadio.Text = "Debian Live 13.3.0 - KDE Edition (approx. 3.2 GB)"
$debianRadio.Font = $boldFont
$debianRadio.Location = New-Object System.Drawing.Point(0, 72)
$debianRadio.Size = New-Object System.Drawing.Size(640, 20)
$distroPanel.Controls.Add($debianRadio)

# Distro selection: Fedora 43 KDE radio button
$fedoraRadio = New-Object System.Windows.Forms.RadioButton
$fedoraRadio.Text = "Fedora 43 - KDE Plasma Desktop (approx. 3.0 GB)"
$fedoraRadio.Font = $boldFont
$fedoraRadio.Location = New-Object System.Drawing.Point(0, 96)
$fedoraRadio.Size = New-Object System.Drawing.Size(640, 20)
$distroPanel.Controls.Add($fedoraRadio)

# Custom ISO checkbox
$customRadio = New-Object System.Windows.Forms.CheckBox
$customRadio.Text = "Use existing ISO file:"
$customRadio.Font = $normalFont
$customRadio.Location = New-Object System.Drawing.Point(10, 142)
$customRadio.Size = New-Object System.Drawing.Size(160, 20)
$isoGroup.Controls.Add($customRadio)

# Custom ISO path textbox
$customIsoTextbox = New-Object System.Windows.Forms.TextBox
$customIsoTextbox.Font = $normalFont
$customIsoTextbox.Location = New-Object System.Drawing.Point(172, 140)
$customIsoTextbox.Size = New-Object System.Drawing.Size(388, 24)
$customIsoTextbox.ReadOnly = $true
$customIsoTextbox.Enabled = $false
$isoGroup.Controls.Add($customIsoTextbox)

# Browse button
$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse..."
$browseButton.Font = $normalFont
$browseButton.Location = New-Object System.Drawing.Point(568, 139)
$browseButton.Size = New-Object System.Drawing.Size(100, 26)
$browseButton.Enabled = $false
$isoGroup.Controls.Add($browseButton)

# Disk info group
$diskGroup = New-Object System.Windows.Forms.GroupBox
$diskGroup.Text = "Disk Information"
$diskGroup.Font = $normalFont
$diskGroup.Location = New-Object System.Drawing.Point(10, 288)
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
$sizeGroup.Text = "Linux Partition Size (for installation after live image boot)"
$sizeGroup.Font = $normalFont
$sizeGroup.Location = New-Object System.Drawing.Point(360, 288)
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
$sizeNumeric.Maximum = 10000
$sizeNumeric.Value = 30
$sizeGroup.Controls.Add($sizeNumeric)

# Size help label
$sizeHelpLabel = New-Object System.Windows.Forms.Label
$sizeHelpLabel.Text = "Minimum: 20 GB, Recommended: 100+ GB"
$sizeHelpLabel.Font = $normalFont
$sizeHelpLabel.Location = New-Object System.Drawing.Point(10, 65)
$sizeHelpLabel.Size = New-Object System.Drawing.Size(310, 20)
$sizeGroup.Controls.Add($sizeHelpLabel)

# Log group
$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = "Installation Log"
$logGroup.Font = $normalFont
$logGroup.Location = New-Object System.Drawing.Point(10, 427)
$logGroup.Size = New-Object System.Drawing.Size(680, 220)
$form.Controls.Add($logGroup)

# Log text box
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(10, 20)
$logBox.Size = New-Object System.Drawing.Size(660, 190)
$logGroup.Controls.Add($logBox)

# Delete ISO checkbox
$deleteIsoCheck = New-Object System.Windows.Forms.CheckBox
$deleteIsoCheck.Text = "Delete ISO file after installation"
$deleteIsoCheck.Font = $normalFont
$deleteIsoCheck.Location = New-Object System.Drawing.Point(10, 657)
$deleteIsoCheck.Size = New-Object System.Drawing.Size(300, 25)
$form.Controls.Add($deleteIsoCheck)

# Auto-restart checkbox
$autoRestartCheck = New-Object System.Windows.Forms.CheckBox
$autoRestartCheck.Text = "Automatically restart and configure UEFI boot"
$autoRestartCheck.Font = $normalFont
$autoRestartCheck.Location = New-Object System.Drawing.Point(10, 682)
$autoRestartCheck.Size = New-Object System.Drawing.Size(300, 25)
$autoRestartCheck.Checked = $true
$form.Controls.Add($autoRestartCheck)

# Start button
$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start Installation"
$startButton.Font = $boldFont
$startButton.Location = New-Object System.Drawing.Point(390, 662)
$startButton.Size = New-Object System.Drawing.Size(140, 35)
$startButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
$startButton.ForeColor = [System.Drawing.Color]::White
$startButton.FlatStyle = "Flat"
$form.Controls.Add($startButton)

# Exit button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Font = $normalFont
$exitButton.Location = New-Object System.Drawing.Point(540, 662)
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
        
        $partitionNumber = if ($cDrive.PartitionNumber) { 
            $cDrive.PartitionNumber 
        } else { 
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
        
        $script:CDriveInfo = @{
            DiskNumber = $cDrive.DiskNumber
            PartitionNumber = $partitionNumber
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
            TotalGB = [math]::Round($volume.Size / 1GB, 2)
        }
        
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

# ============================================================
# DISK PLAN DIALOG
# ============================================================
# Shows the user a clear before/after view of their disk layout,
# lets them choose whether to use existing free space for the
# 7 GB live partition, and requires explicit confirmation before
# any destructive operation begins.
# ============================================================
function Get-DiskLayoutText {
    param(
        [int]$DiskNumber
    )
    # Returns an array of text lines describing the current partition layout of a disk
    $disk = Get-Disk -Number $DiskNumber
    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Sort-Object Offset
    $lines = @()
    
    if (-not $partitions -or $partitions.Count -eq 0) {
        $lines += "  [Entire disk is unallocated]  $([math]::Round($disk.Size / 1GB, 2)) GB"
        return $lines
    }
    
    $previousEnd = [int64]0
    foreach ($part in $partitions) {
        if ($part.Offset -gt ($previousEnd + 1MB)) {
            $gapGB = [math]::Round(($part.Offset - $previousEnd) / 1GB, 2)
            if ($gapGB -gt 0.01) {
                $lines += "  [Unallocated]             $gapGB GB"
            }
        }
        
        $sizeGB = [math]::Round($part.Size / 1GB, 2)
        $label = if ($part.DriveLetter -eq 'C') { 
            "C: (Windows/NTFS)    " 
        } elseif ($part.DriveLetter) { 
            "$($part.DriveLetter): drive               " 
        } elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") { 
            "Recovery             " 
        } elseif ($part.IsSystem) { 
            "EFI System (ESP)     " 
        } elseif ($part.GptType -match "e3c9e316") {
            "Microsoft Reserved   "
        } else { 
            "Partition            " 
        }
        
        $freeNote = ""
        if ($part.DriveLetter -eq 'C') {
            try {
                $vol = Get-Volume -DriveLetter C -ErrorAction Stop
                $freeNote = "  (Free: $([math]::Round($vol.SizeRemaining / 1GB, 2)) GB)"
            } catch {}
        } elseif ($part.DriveLetter) {
            try {
                $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                if ($vol.SizeRemaining) {
                    $freeNote = "  (Free: $([math]::Round($vol.SizeRemaining / 1GB, 2)) GB)"
                }
            } catch {}
        }
        
        $lines += "  $label $sizeGB GB$freeNote"
        $previousEnd = $part.Offset + $part.Size
    }
    # Trailing
    if ($disk.Size -gt ($previousEnd + 1MB)) {
        $trailGB = [math]::Round(($disk.Size - $previousEnd) / 1GB, 2)
        if ($trailGB -gt 0.01) {
            $lines += "  [Unallocated]             $trailGB GB"
        }
    }
    
    return $lines
}

function Get-DiskUnallocatedGB {
    param(
        [int]$DiskNumber,
        [int64]$AfterOffset = 0
    )
    # Returns total unallocated GB on a disk, optionally only after a given offset
    $disk = Get-Disk -Number $DiskNumber
    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Sort-Object Offset
    
    $total = [int64]0
    $previousEnd = [int64]0
    
    if ($partitions) {
        foreach ($part in $partitions) {
            $gap = $part.Offset - $previousEnd
            if ($gap -gt 1MB -and $previousEnd -ge $AfterOffset) {
                $total += $gap
            }
            $previousEnd = $part.Offset + $part.Size
        }
    }
    $trailing = $disk.Size - $previousEnd
    if ($trailing -gt 1MB -and $previousEnd -ge $AfterOffset) {
        $total += $trailing
    }
    
    return [math]::Round($total / 1GB, 2)
}

function Show-DiskPlan {
    param(
        [string]$DistroName,
        [int]$LinuxSizeGB
    )
    
    $bootPartSizeGB = $script:MinPartitionSizeGB  # 7 GB
    $totalNeededGB = $LinuxSizeGB + $bootPartSizeGB
    
    # ---- Enumerate all suitable disks ----
    $allDisks = Get-Disk | Where-Object { 
        $_.OperationalStatus -eq 'Online' -and $_.Size -gt 10GB
    } | Sort-Object Number
    
    $cDiskNumber = $script:CDriveInfo.DiskNumber
    
    # Build dropdown items: C: disk first, then others
    $diskItems = @()
    foreach ($d in $allDisks) {
        $dSizeGB = [math]::Round($d.Size / 1GB, 1)
        $dFreeGB = Get-DiskUnallocatedGB -DiskNumber $d.Number
        $busType = if ($d.BusType) { $d.BusType } else { "Unknown" }
        $model = if ($d.Model) { $d.Model.Trim() } else { "Disk" }
        
        # Check what drive letters are on this disk
        $letters = (Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | 
            Where-Object { $_.DriveLetter } | 
            ForEach-Object { "$($_.DriveLetter):" }) -join ", "
        $letterInfo = if ($letters) { " [$letters]" } else { "" }
        
        $isCDisk = ($d.Number -eq $cDiskNumber)
        $prefix = if ($isCDisk) { "Disk $($d.Number) (Windows)" } else { "Disk $($d.Number)" }
        
        $diskItems += [PSCustomObject]@{
            Number = $d.Number
            Label = "$prefix - $model - $dSizeGB GB ($busType)$letterInfo - Free: $dFreeGB GB"
            IsCDisk = $isCDisk
            TotalGB = $dSizeGB
            FreeGB = $dFreeGB
        }
    }
    
    # ---- Build the dialog ----
    $planForm = New-Object System.Windows.Forms.Form
    $planForm.Text = "Disk Plan - Review Before Proceeding"
    $planForm.Size = New-Object System.Drawing.Size(720, 780)
    $planForm.StartPosition = "CenterParent"
    $planForm.FormBorderStyle = "FixedDialog"
    $planForm.MaximizeBox = $false
    $planForm.MinimizeBox = $false
    
    $planFont = New-Object System.Drawing.Font("Segoe UI", 9)
    $planBoldFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $planHeaderFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $planMonoFont = New-Object System.Drawing.Font("Consolas", 9)
    
    $yPos = 12
    
    # Title
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Review Disk Changes for $DistroName"
    $titleLabel.Font = $planHeaderFont
    $titleLabel.Location = New-Object System.Drawing.Point(16, $yPos)
    $titleLabel.Size = New-Object System.Drawing.Size(670, 26)
    $planForm.Controls.Add($titleLabel)
    $yPos += 32
    
    # Warning banner
    $warningPanel = New-Object System.Windows.Forms.Panel
    $warningPanel.Location = New-Object System.Drawing.Point(16, $yPos)
    $warningPanel.Size = New-Object System.Drawing.Size(670, 42)
    $warningPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 220)
    $warningPanel.BorderStyle = "FixedSingle"
    $planForm.Controls.Add($warningPanel)
    
    $warningLabel = New-Object System.Windows.Forms.Label
    $warningLabel.Text = [char]0x26A0 + "  These changes modify your disk's partition table. No data should be lost, but make sure you have a backup of important files before proceeding."
    $warningLabel.Font = $planFont
    $warningLabel.Location = New-Object System.Drawing.Point(8, 4)
    $warningLabel.Size = New-Object System.Drawing.Size(650, 34)
    $warningPanel.Controls.Add($warningLabel)
    $yPos += 52
    
    # ---- TARGET DISK SELECTOR ----
    $diskSelectGroup = New-Object System.Windows.Forms.GroupBox
    $diskSelectGroup.Text = "Target Disk"
    $diskSelectGroup.Font = $planBoldFont
    $diskSelectGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $diskSelectGroup.Size = New-Object System.Drawing.Size(670, 56)
    $planForm.Controls.Add($diskSelectGroup)
    
    $diskCombo = New-Object System.Windows.Forms.ComboBox
    $diskCombo.Font = $planFont
    $diskCombo.DropDownStyle = "DropDownList"
    $diskCombo.Location = New-Object System.Drawing.Point(10, 22)
    $diskCombo.Size = New-Object System.Drawing.Size(648, 24)
    $diskSelectGroup.Controls.Add($diskCombo)
    
    foreach ($item in $diskItems) {
        $diskCombo.Items.Add($item.Label) | Out-Null
    }
    # Default to the C: disk
    $cIndex = 0
    for ($i = 0; $i -lt $diskItems.Count; $i++) {
        if ($diskItems[$i].IsCDisk) { $cIndex = $i; break }
    }
    $diskCombo.SelectedIndex = $cIndex
    $yPos += 66
    
    # ---- CURRENT LAYOUT ----
    $currentGroup = New-Object System.Windows.Forms.GroupBox
    $currentGroup.Text = "Current Disk Layout"
    $currentGroup.Font = $planBoldFont
    $currentGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $currentGroup.Size = New-Object System.Drawing.Size(670, 150)
    $planForm.Controls.Add($currentGroup)
    
    $currentText = New-Object System.Windows.Forms.TextBox
    $currentText.Multiline = $true
    $currentText.ReadOnly = $true
    $currentText.ScrollBars = "Vertical"
    $currentText.Font = $planMonoFont
    $currentText.Location = New-Object System.Drawing.Point(10, 20)
    $currentText.Size = New-Object System.Drawing.Size(648, 120)
    $currentText.BackColor = [System.Drawing.Color]::White
    $currentGroup.Controls.Add($currentText)
    $yPos += 160
    
    # ---- STRATEGY SELECTION ----
    $strategyGroup = New-Object System.Windows.Forms.GroupBox
    $strategyGroup.Text = "Installation Strategy"
    $strategyGroup.Font = $planBoldFont
    $strategyGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $strategyGroup.Size = New-Object System.Drawing.Size(670, 80)
    $planForm.Controls.Add($strategyGroup)
    
    $stratPanel = New-Object System.Windows.Forms.Panel
    $stratPanel.Location = New-Object System.Drawing.Point(10, 18)
    $stratPanel.Size = New-Object System.Drawing.Size(648, 56)
    $strategyGroup.Controls.Add($stratPanel)
    
    $radioShrink = New-Object System.Windows.Forms.RadioButton
    $radioShrink.Font = $planFont
    $radioShrink.Location = New-Object System.Drawing.Point(0, 0)
    $radioShrink.Size = New-Object System.Drawing.Size(640, 20)
    $radioShrink.Checked = $true
    $stratPanel.Controls.Add($radioShrink)
    
    $radioFreeAll = New-Object System.Windows.Forms.RadioButton
    $radioFreeAll.Font = $planFont
    $radioFreeAll.Location = New-Object System.Drawing.Point(0, 24)
    $radioFreeAll.Size = New-Object System.Drawing.Size(640, 20)
    $stratPanel.Controls.Add($radioFreeAll)
    $yPos += 88
    
    # ---- PLANNED CHANGES ----
    $changesGroup = New-Object System.Windows.Forms.GroupBox
    $changesGroup.Text = "Planned Changes"
    $changesGroup.Font = $planBoldFont
    $changesGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $changesGroup.Size = New-Object System.Drawing.Size(670, 100)
    $planForm.Controls.Add($changesGroup)
    
    $changesText = New-Object System.Windows.Forms.TextBox
    $changesText.Multiline = $true
    $changesText.ReadOnly = $true
    $changesText.Font = $planMonoFont
    $changesText.Location = New-Object System.Drawing.Point(10, 20)
    $changesText.Size = New-Object System.Drawing.Size(648, 70)
    $changesText.BackColor = [System.Drawing.Color]::White
    $changesGroup.Controls.Add($changesText)
    $yPos += 110
    
    # ---- AFTER LAYOUT ----
    $afterGroup = New-Object System.Windows.Forms.GroupBox
    $afterGroup.Text = "Disk Layout After Changes"
    $afterGroup.Font = $planBoldFont
    $afterGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $afterGroup.Size = New-Object System.Drawing.Size(670, 130)
    $planForm.Controls.Add($afterGroup)
    
    $afterText = New-Object System.Windows.Forms.TextBox
    $afterText.Multiline = $true
    $afterText.ReadOnly = $true
    $afterText.ScrollBars = "Vertical"
    $afterText.Font = $planMonoFont
    $afterText.Location = New-Object System.Drawing.Point(10, 20)
    $afterText.Size = New-Object System.Drawing.Size(648, 100)
    $afterText.BackColor = [System.Drawing.Color]::White
    $afterGroup.Controls.Add($afterText)
    $yPos += 140
    
    # Track selected disk number and shrink info
    $script:DiskPlanStrategy = "shrink_all"
    $script:DiskPlanTargetDisk = $cDiskNumber
    $script:DiskPlanShrinkLetter = $null
    $script:DiskPlanShrinkAmount = 0
    
    # ---- Master update function ----
    # Rebuilds everything based on the selected disk and strategy radio
    $updateAll = {
        $selIndex = $diskCombo.SelectedIndex
        if ($selIndex -lt 0) { return }
        $selDisk = $diskItems[$selIndex]
        $selDiskNum = $selDisk.Number
        $isTargetCDisk = $selDisk.IsCDisk
        
        $script:DiskPlanTargetDisk = $selDiskNum
        
        # Update current layout text
        $layoutLines = Get-DiskLayoutText -DiskNumber $selDiskNum
        $diskObj = Get-Disk -Number $selDiskNum
        $dTotalGB = [math]::Round($diskObj.Size / 1GB, 2)
        $currentGroup.Text = "Current Disk Layout  (Disk $selDiskNum - $dTotalGB GB)"
        
        $totalFreeGB = Get-DiskUnallocatedGB -DiskNumber $selDiskNum
        if ($totalFreeGB -gt 0.01) {
            $layoutLines += ""
            $layoutLines += "  Total unallocated space: $totalFreeGB GB"
        }
        $currentText.Text = ($layoutLines -join "`r`n")
        
        if ($isTargetCDisk) {
            # ---- C: disk strategies ----
            $cPartition = Get-Partition -DriveLetter C
            $cSizeGB = [math]::Round($cPartition.Size / 1GB, 2)
            $cFreeGB = $script:CDriveInfo.FreeGB
            $cPartitionEnd = $cPartition.Offset + $cPartition.Size
            $usableFreeGB = Get-DiskUnallocatedGB -DiskNumber $selDiskNum -AfterOffset $cPartitionEnd
            
            $canFreeAll = ($usableFreeGB -ge ($totalNeededGB + 1))
            $canFreeBoot = ($usableFreeGB -ge ($bootPartSizeGB + 1))
            
            # Configure radio buttons
            $radioShrink.Text = "Shrink C: by $totalNeededGB GB for both Linux ($LinuxSizeGB GB) and boot partition ($bootPartSizeGB GB)"
            $radioShrink.Visible = $true
            $radioShrink.Enabled = $true
            
            if ($canFreeAll) {
                $radioFreeAll.Text = "Use existing unallocated space ($([math]::Round($usableFreeGB, 1)) GB available) - no shrink needed"
                $radioFreeAll.Visible = $true
                $radioFreeAll.Enabled = $true
            } elseif ($canFreeBoot) {
                $radioFreeAll.Text = "Use existing free space for 7 GB boot partition, shrink C: by $LinuxSizeGB GB for Linux only"
                $radioFreeAll.Visible = $true
                $radioFreeAll.Enabled = $true
            } else {
                $radioFreeAll.Visible = $false
                $radioFreeAll.Checked = $false
                if (-not $radioShrink.Checked) { $radioShrink.Checked = $true }
            }
            
            $strategyGroup.Visible = $true
            
            # Determine strategy
            $strategy = "shrink_all"
            if ($radioFreeAll.Visible -and $radioFreeAll.Checked) {
                if ($canFreeAll) { $strategy = "use_free_all" }
                elseif ($canFreeBoot) { $strategy = "use_free_boot" }
            }
            $script:DiskPlanStrategy = $strategy
            
            # Build changes & after text
            $changeLines = @()
            $afterLines = @()
            $partitions = Get-Partition -DiskNumber $selDiskNum | Sort-Object Offset
            
            switch ($strategy) {
                "shrink_all" {
                    $newCSizeGB = [math]::Round($cSizeGB - $totalNeededGB, 2)
                    $changeLines += "  1. Shrink C: partition from $cSizeGB GB to $newCSizeGB GB  (-$totalNeededGB GB)"
                    $changeLines += "  2. Create 7 GB FAT32 boot partition (LINUX_LIVE) with $DistroName files"
                    $changeLines += "  3. Leave $LinuxSizeGB GB unallocated for Linux installation"
                    $changeLines += "  4. Configure UEFI boot entry for $DistroName"
                    
                    foreach ($part in $partitions) {
                        $sGB = [math]::Round($part.Size / 1GB, 2)
                        if ($part.DriveLetter -eq 'C') {
                            $afterLines += "  C: (Windows/NTFS)     $newCSizeGB GB"
                            $afterLines += "  [Unallocated - Linux]  $LinuxSizeGB GB  <-- for Linux installer"
                            $afterLines += "  LINUX_LIVE (FAT32)     $bootPartSizeGB GB  <-- $DistroName live boot"
                        } elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") {
                            $afterLines += "  Recovery               $sGB GB"
                        } elseif ($part.IsSystem) {
                            $afterLines += "  EFI System (ESP)       $sGB GB"
                        } elseif ($part.GptType -match "e3c9e316") {
                            $afterLines += "  Microsoft Reserved     $sGB GB"
                        } elseif ($part.DriveLetter) {
                            $afterLines += "  $($part.DriveLetter): drive               $sGB GB"
                        } else {
                            $afterLines += "  Partition              $sGB GB"
                        }
                    }
                }
                "use_free_all" {
                    $changeLines += "  1. C: partition is NOT modified (stays at $cSizeGB GB)"
                    $changeLines += "  2. Create 7 GB FAT32 boot partition (LINUX_LIVE) in existing free space"
                    $changeLines += "  3. Remaining ~$([math]::Round($usableFreeGB - $bootPartSizeGB, 1)) GB stays unallocated for Linux"
                    $changeLines += "  4. Configure UEFI boot entry for $DistroName"
                    
                    foreach ($part in $partitions) {
                        $sGB = [math]::Round($part.Size / 1GB, 2)
                        if ($part.DriveLetter -eq 'C') {
                            $afterLines += "  C: (Windows/NTFS)     $sGB GB  (unchanged)"
                        } elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") {
                            $afterLines += "  Recovery               $sGB GB"
                        } elseif ($part.IsSystem) {
                            $afterLines += "  EFI System (ESP)       $sGB GB"
                        } elseif ($part.GptType -match "e3c9e316") {
                            $afterLines += "  Microsoft Reserved     $sGB GB"
                        } elseif ($part.DriveLetter) {
                            $afterLines += "  $($part.DriveLetter): drive               $sGB GB"
                        } else {
                            $afterLines += "  Partition              $sGB GB"
                        }
                    }
                    $remainFreeGB = [math]::Round($usableFreeGB - $bootPartSizeGB, 1)
                    $afterLines += "  [Unallocated - Linux]  $remainFreeGB GB  <-- for Linux installer"
                    $afterLines += "  LINUX_LIVE (FAT32)     $bootPartSizeGB GB  <-- $DistroName live boot"
                }
                "use_free_boot" {
                    $newCSizeGB = [math]::Round($cSizeGB - $LinuxSizeGB, 2)
                    $changeLines += "  1. Shrink C: partition from $cSizeGB GB to $newCSizeGB GB  (-$LinuxSizeGB GB)"
                    $changeLines += "  2. Create 7 GB FAT32 boot partition (LINUX_LIVE) in existing free space"
                    $changeLines += "  3. Leave $LinuxSizeGB GB (from C: shrink) unallocated for Linux"
                    $changeLines += "  4. Configure UEFI boot entry for $DistroName"
                    
                    foreach ($part in $partitions) {
                        $sGB = [math]::Round($part.Size / 1GB, 2)
                        if ($part.DriveLetter -eq 'C') {
                            $afterLines += "  C: (Windows/NTFS)     $newCSizeGB GB"
                            $afterLines += "  [Unallocated - Linux]  $LinuxSizeGB GB  <-- for Linux installer"
                        } elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") {
                            $afterLines += "  Recovery               $sGB GB"
                        } elseif ($part.IsSystem) {
                            $afterLines += "  EFI System (ESP)       $sGB GB"
                        } elseif ($part.GptType -match "e3c9e316") {
                            $afterLines += "  Microsoft Reserved     $sGB GB"
                        } elseif ($part.DriveLetter) {
                            $afterLines += "  $($part.DriveLetter): drive               $sGB GB"
                        } else {
                            $afterLines += "  Partition              $sGB GB"
                        }
                    }
                    $afterLines += "  LINUX_LIVE (FAT32)     $bootPartSizeGB GB  <-- $DistroName live boot"
                }
            }
            
            $changesText.Text = ($changeLines -join "`r`n")
            $afterText.Text = ($afterLines -join "`r`n")
            
        } else {
            # ---- Other disk ----
            # Find shrinkable partitions on the target disk
            # Only NTFS can be shrunk by Windows (Resize-Partition / diskpart)
            $shrinkablePartitions = @()
            $partitions = Get-Partition -DiskNumber $selDiskNum -ErrorAction SilentlyContinue | Sort-Object Offset
            if ($partitions) {
                foreach ($part in $partitions) {
                    if ($part.DriveLetter) {
                        try {
                            $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                            if ($vol.FileSystem -eq "NTFS" -and $vol.SizeRemaining -gt ($totalNeededGB * 1GB)) {
                                $shrinkablePartitions += [PSCustomObject]@{
                                    DriveLetter = $part.DriveLetter
                                    SizeGB = [math]::Round($part.Size / 1GB, 2)
                                    FreeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
                                    PartitionNumber = $part.PartitionNumber
                                }
                            }
                        } catch {}
                    }
                }
            }
            
            $diskFreeGB = $selDisk.FreeGB
            $hasFreeSpace = ($diskFreeGB -ge ($bootPartSizeGB + 1))
            $hasShrinkable = ($shrinkablePartitions.Count -gt 0)
            
            # Identify non-NTFS partitions so we can explain why they can't be shrunk
            $nonNtfsPartitions = @()
            if ($partitions) {
                foreach ($part in $partitions) {
                    if ($part.DriveLetter) {
                        try {
                            $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                            if ($vol.FileSystem -ne "NTFS" -and $vol.FileSystem) {
                                $nonNtfsPartitions += [PSCustomObject]@{
                                    DriveLetter = $part.DriveLetter
                                    FileSystem = $vol.FileSystem
                                    SizeGB = [math]::Round($part.Size / 1GB, 2)
                                }
                            }
                        } catch {}
                    }
                }
            }
            
            # Configure radio buttons for other-drive strategies
            if ($hasFreeSpace) {
                $radioShrink.Text = "Use existing unallocated space ($([math]::Round($diskFreeGB, 1)) GB) on Disk $selDiskNum"
                $radioShrink.Visible = $true
                $radioShrink.Enabled = $true
                if (-not $radioShrink.Checked -and -not $radioFreeAll.Checked) {
                    $radioShrink.Checked = $true
                }
            } else {
                $radioShrink.Visible = $false
                $radioShrink.Checked = $false
            }
            
            if ($hasShrinkable) {
                # Pick the partition with the most free space as the default shrink target
                $bestShrink = $shrinkablePartitions | Sort-Object FreeGB -Descending | Select-Object -First 1
                $radioFreeAll.Text = "Shrink $($bestShrink.DriveLetter): ($($bestShrink.SizeGB) GB, $($bestShrink.FreeGB) GB free) on Disk $selDiskNum to make space"
                $radioFreeAll.Visible = $true
                $radioFreeAll.Enabled = $true
                if (-not $hasFreeSpace) {
                    $radioFreeAll.Checked = $true
                }
            } else {
                $radioFreeAll.Visible = $false
                $radioFreeAll.Checked = $false
            }
            
            if (-not $hasFreeSpace -and -not $hasShrinkable) {
                $radioShrink.Text = "No unallocated space or shrinkable partitions on Disk $selDiskNum"
                $radioShrink.Visible = $true
                $radioShrink.Enabled = $false
                $radioShrink.Checked = $false
                $radioFreeAll.Visible = $false
                
                # Show explanation for non-NTFS partitions
                if ($nonNtfsPartitions.Count -gt 0) {
                    $fsTypes = ($nonNtfsPartitions | ForEach-Object { "$($_.DriveLetter): ($($_.FileSystem))" }) -join ", "
                    $radioFreeAll.Text = "Cannot shrink $fsTypes - only NTFS partitions can be resized by Windows"
                    $radioFreeAll.Visible = $true
                    $radioFreeAll.Enabled = $false
                    $radioFreeAll.Checked = $false
                }
            }
            
            $strategyGroup.Visible = $true
            
            # Determine strategy based on what's available and which radio is checked
            # When only one option exists, use it regardless of radio state
            if ($hasShrinkable -and -not $hasFreeSpace) {
                # Only shrink is available
                $usingShrink = $true
            } elseif ($hasFreeSpace -and -not $hasShrinkable) {
                # Only free space is available
                $usingShrink = $false
            } elseif ($hasFreeSpace -and $hasShrinkable) {
                # Both available — check which radio is selected
                $usingShrink = $radioFreeAll.Checked
            } else {
                $usingShrink = $false
            }
            
            if ($usingShrink) {
                $script:DiskPlanStrategy = "other_drive_shrink"
                $script:DiskPlanShrinkLetter = $bestShrink.DriveLetter
                $script:DiskPlanShrinkAmount = $totalNeededGB
            } else {
                $script:DiskPlanStrategy = "other_drive"
                $script:DiskPlanShrinkLetter = $null
                $script:DiskPlanShrinkAmount = 0
            }
            
            $changeLines = @()
            $afterLines = @()
            
            if ($usingShrink) {
                $shrinkTarget = $bestShrink
                $newPartSizeGB = [math]::Round($shrinkTarget.SizeGB - $totalNeededGB, 2)
                $changeLines += "  1. C: partition is NOT modified (different disk selected)"
                $changeLines += "  2. Shrink $($shrinkTarget.DriveLetter): from $($shrinkTarget.SizeGB) GB to $newPartSizeGB GB  (-$totalNeededGB GB)"
                $changeLines += "  3. Create 7 GB FAT32 boot partition (LINUX_LIVE) on Disk $selDiskNum"
                $changeLines += "  4. Leave $LinuxSizeGB GB unallocated for Linux installation"
                $changeLines += "  5. Configure UEFI boot entry for $DistroName"
                
                if ($partitions) {
                    foreach ($part in $partitions) {
                        $sGB = [math]::Round($part.Size / 1GB, 2)
                        if ($part.DriveLetter -eq $shrinkTarget.DriveLetter) {
                            $afterLines += "  $($part.DriveLetter): drive (NTFS)       $newPartSizeGB GB  (shrunk)"
                            $afterLines += "  [Unallocated - Linux]  $LinuxSizeGB GB  <-- for Linux installer"
                            $afterLines += "  LINUX_LIVE (FAT32)     $bootPartSizeGB GB  <-- $DistroName live boot"
                        } elseif ($part.DriveLetter) {
                            $afterLines += "  $($part.DriveLetter): drive               $sGB GB"
                        } elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") {
                            $afterLines += "  Recovery               $sGB GB"
                        } elseif ($part.IsSystem) {
                            $afterLines += "  EFI System (ESP)       $sGB GB"
                        } else {
                            $afterLines += "  Partition              $sGB GB"
                        }
                    }
                }
            } else {
                if ($hasFreeSpace) {
                    $changeLines += "  1. C: partition is NOT modified (different disk selected)"
                    $changeLines += "  2. Create 7 GB FAT32 boot partition (LINUX_LIVE) on Disk $selDiskNum"
                    $changeLines += "  3. Remaining unallocated space on Disk $selDiskNum available for Linux"
                    $changeLines += "  4. Configure UEFI boot entry for $DistroName"
                    
                    if ($partitions) {
                        foreach ($part in $partitions) {
                            $sGB = [math]::Round($part.Size / 1GB, 2)
                            if ($part.DriveLetter) {
                                $afterLines += "  $($part.DriveLetter): drive               $sGB GB  (unchanged)"
                            } elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") {
                                $afterLines += "  Recovery               $sGB GB"
                            } elseif ($part.IsSystem) {
                                $afterLines += "  EFI System (ESP)       $sGB GB"
                            } else {
                                $afterLines += "  Partition              $sGB GB"
                            }
                        }
                    }
                    
                    $remainFreeGB = [math]::Round($diskFreeGB - $bootPartSizeGB, 1)
                    if ($remainFreeGB -gt 0) {
                        $afterLines += "  [Unallocated - Linux]  $remainFreeGB GB  <-- for Linux installer"
                    }
                    $afterLines += "  LINUX_LIVE (FAT32)     $bootPartSizeGB GB  <-- $DistroName live boot"
                } else {
                    # No free space and no shrinkable partitions
                    $changeLines += "  Cannot proceed with this disk."
                    $changeLines += ""
                    if ($nonNtfsPartitions.Count -gt 0) {
                        foreach ($nfp in $nonNtfsPartitions) {
                            $changeLines += "  $($nfp.DriveLetter): is $($nfp.FileSystem) ($($nfp.SizeGB) GB) - cannot be shrunk by Windows."
                        }
                        $changeLines += ""
                        $changeLines += "  To use this disk, you would need to:"
                        $changeLines += "    - Back up your data from the drive"
                        $changeLines += "    - Shrink or delete the partition using Disk Management"
                        $changeLines += "    - Re-run ULLI (it will detect the free space)"
                    } else {
                        $changeLines += "  No unallocated space available on this disk."
                    }
                    
                    # Show current layout unchanged
                    if ($partitions) {
                        foreach ($part in $partitions) {
                            $sGB = [math]::Round($part.Size / 1GB, 2)
                            if ($part.DriveLetter) {
                                $afterLines += "  $($part.DriveLetter): drive               $sGB GB  (unchanged)"
                            } elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") {
                                $afterLines += "  Recovery               $sGB GB"
                            } elseif ($part.IsSystem) {
                                $afterLines += "  EFI System (ESP)       $sGB GB"
                            } else {
                                $afterLines += "  Partition              $sGB GB"
                            }
                        }
                    }
                    $afterLines += ""
                    $afterLines += "  (No changes - disk cannot be used as-is)"
                }
            }
            
            $changesText.Text = ($changeLines -join "`r`n")
            $afterText.Text = ($afterLines -join "`r`n")
        }
    }
    
    # Wire events
    $diskCombo.Add_SelectedIndexChanged({
        # Reset to first radio when switching disks
        $radioShrink.Checked = $true
        & $updateAll
    })
    $radioShrink.Add_CheckedChanged({ & $updateAll })
    $radioFreeAll.Add_CheckedChanged({ & $updateAll })
    
    # Initial update
    & $updateAll
    
    # ---- BUTTONS ----
    $confirmButton = New-Object System.Windows.Forms.Button
    $confirmButton.Text = "Confirm && Proceed"
    $confirmButton.Font = $planBoldFont
    $confirmButton.Size = New-Object System.Drawing.Size(160, 38)
    $confirmButton.Location = New-Object System.Drawing.Point(362, $yPos)
    $confirmButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
    $confirmButton.ForeColor = [System.Drawing.Color]::White
    $confirmButton.FlatStyle = "Flat"
    $planForm.Controls.Add($confirmButton)
    
    $cancelPlanButton = New-Object System.Windows.Forms.Button
    $cancelPlanButton.Text = "Cancel"
    $cancelPlanButton.Font = $planFont
    $cancelPlanButton.Size = New-Object System.Drawing.Size(120, 38)
    $cancelPlanButton.Location = New-Object System.Drawing.Point(532, $yPos)
    $planForm.Controls.Add($cancelPlanButton)
    
    $script:DiskPlanApproved = $false
    
    $confirmButton.Add_Click({
        # Validate the selected disk has enough space
        $selIndex = $diskCombo.SelectedIndex
        $selDisk = $diskItems[$selIndex]
        
        if (-not $selDisk.IsCDisk) {
            $strat = $script:DiskPlanStrategy
            if ($strat -eq "other_drive") {
                if ($selDisk.FreeGB -lt ($bootPartSizeGB + 1)) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Disk $($selDisk.Number) does not have enough unallocated space.`n`n" +
                        "Need at least $($bootPartSizeGB + 1) GB of free space, but only $($selDisk.FreeGB) GB available.`n`n" +
                        "Please select a different disk or choose to shrink a partition.",
                        "Insufficient Space on Target Disk",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    return
                }
            } elseif ($strat -eq "other_drive_shrink") {
                # Already validated in the plan view that the partition has enough space
            } elseif ($strat -eq "other_drive" -and -not ($selDisk.FreeGB -ge ($bootPartSizeGB + 1))) {
                # No free space and couldn't shrink — shouldn't be confirmable
                [System.Windows.Forms.MessageBox]::Show(
                    "Disk $($selDisk.Number) cannot be used as-is.`n`n" +
                    "It has no unallocated space and no NTFS partitions that can be shrunk.`n" +
                    "You may need to shrink or remove a partition manually first.",
                    "Cannot Use Target Disk",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            } else {
                # No valid strategy selected
                [System.Windows.Forms.MessageBox]::Show(
                    "Disk $($selDisk.Number) has no unallocated space and no shrinkable NTFS partitions.`n`n" +
                    "Please select a different disk.",
                    "Cannot Use Target Disk",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }
        }
        
        $script:DiskPlanApproved = $true
        $planForm.Close()
    })
    
    $cancelPlanButton.Add_Click({
        $script:DiskPlanApproved = $false
        $planForm.Close()
    })
    
    # Resize form to fit content
    $planForm.ClientSize = New-Object System.Drawing.Size(702, ($yPos + 52))
    
    $planForm.ShowDialog($form)
    
    return @{
        Approved = $script:DiskPlanApproved
        Strategy = $script:DiskPlanStrategy
        TargetDiskNumber = $script:DiskPlanTargetDisk
        ShrinkDriveLetter = $script:DiskPlanShrinkLetter
        ShrinkAmountGB = $script:DiskPlanShrinkAmount
    }
}

function Verify-ISOChecksum {
    param(
        [string]$FilePath
    )
    
    Log-Message "Verifying ISO checksum..."
    Set-Status "Verifying ISO integrity..."
    
    try {
        $expectedHash = if ($ubuntuRadio.Checked) { $script:UbuntuChecksum } elseif ($kubuntuRadio.Checked) { $script:KubuntuChecksum } elseif ($debianRadio.Checked) { $script:DebianChecksum } elseif ($fedoraRadio.Checked) { $script:FedoraChecksum } else { $script:ExpectedChecksum }
        Log-Message "Expected SHA256: $expectedHash"
        
        # Calculate actual checksum
        Log-Message "Calculating SHA256 checksum of downloaded ISO (this may take a minute)..."
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower()
        Log-Message "Actual SHA256:   $actualHash"
        
        if ($actualHash -eq $expectedHash) {
            Log-Message "[PASS] Checksum verification PASSED - ISO is authentic!"
            return $true
        } else {
            Log-Message "[FAIL] Checksum verification FAILED - ISO may be corrupted or tampered!" -Error
            
            $response = [System.Windows.Forms.MessageBox]::Show(
                "The ISO file checksum does not match the expected checksum!`n`n" +
                "Expected: $expectedHash`n" +
                "Actual:   $actualHash`n`n" +
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
                } catch {
                    Log-Message "Error deleting ISO: $_" -Error
                }
            }
            
            return $false
        }
    }
    catch {
        Log-Message "Error calculating checksum: $_" -Error
        
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
        [string]$Destination
    )
    
    # Determine distro-specific settings
    if ($ubuntuRadio.Checked) {
        $isoName = "Ubuntu 24.04.4 LTS"
        $expectedSize = "approximately 5.9 GB"
        $mirrors = $script:UbuntuMirrors
    } elseif ($kubuntuRadio.Checked) {
        $isoName = "Kubuntu 24.04.4 LTS"
        $expectedSize = "approximately 4.2 GB"
        $mirrors = $script:KubuntuMirrors
    } elseif ($debianRadio.Checked) {
        $isoName = "Debian Live 13.3.0 KDE"
        $expectedSize = "approximately 3.2 GB"
        $mirrors = $script:DebianMirrors
    } elseif ($fedoraRadio.Checked) {
        $isoName = "Fedora 43 KDE Plasma Desktop"
        $expectedSize = "approximately 3.0 GB"
        $mirrors = $script:FedoraMirrors
    } else {
        $isoName = "Linux Mint 22.3 Zena (Cinnamon)"
        $expectedSize = "approximately 2.9 GB"
        $mirrors = $script:MintMirrors
    }
    
    Log-Message "Downloading $isoName ISO ($expectedSize)..."
    Log-Message "This may take a while depending on your internet speed..."
    
    foreach ($i in 0..($mirrors.Count - 1)) {
        $mirror = $mirrors[$i]
        Log-Message "Trying mirror $($i + 1)/$($mirrors.Count): $($mirror.Split('/')[2])"
        Set-Status "Connecting to mirror..."
        
        try {
            Add-Type -AssemblyName System.Net.Http
            
            $httpClient = New-Object System.Net.Http.HttpClient
            $httpClient.Timeout = [TimeSpan]::FromMinutes(60)
            
            $response = $httpClient.GetAsync($mirror, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
            
            if ($response.IsSuccessStatusCode) {
                $totalBytes = $response.Content.Headers.ContentLength
                $totalMB = [math]::Round($totalBytes / 1MB, 1)
                Log-Message "File size: $totalMB MB"
                
                $fileStream = [System.IO.File]::Create($Destination)
                $downloadStream = $response.Content.ReadAsStreamAsync().Result
                
                $buffer = New-Object byte[] 81920
                $totalRead = 0
                $lastUpdate = [DateTime]::Now
                $updateInterval = [TimeSpan]::FromMilliseconds(500)
                
                Set-Status "Downloading..."
                
                while ($true) {
                    $bytesRead = $downloadStream.Read($buffer, 0, $buffer.Length)
                    
                    if ($bytesRead -eq 0) {
                        break
                    }
                    
                    $fileStream.Write($buffer, 0, $bytesRead)
                    $totalRead += $bytesRead
                    
                    $now = [DateTime]::Now
                    if (($now - $lastUpdate) -gt $updateInterval) {
                        $percent = [int](($totalRead / $totalBytes) * 100)
                        $mbDownloaded = [math]::Round($totalRead / 1MB, 1)
                        
                        $progressBar.Value = $percent
                        $statusLabel.Text = "Downloading: $percent% - $mbDownloaded MB / $totalMB MB"
                        Set-Status "Downloading: $percent% - $mbDownloaded MB / $totalMB MB"
                        
                        [System.Windows.Forms.Application]::DoEvents()
                        $lastUpdate = $now
                    }
                }
                
                $fileStream.Close()
                $downloadStream.Close()
                $response.Dispose()
                $httpClient.Dispose()
                
                $progressBar.Value = 100
                Set-Status "Download complete!"
                $statusLabel.Text = "Download complete!"
                Start-Sleep -Milliseconds 500
                $progressBar.Value = 0
                $statusLabel.Text = ""
                
                $fileInfo = Get-Item $Destination
                $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
                Log-Message "Downloaded file size: $fileSizeGB GB"
                
                if ($fileInfo.Length -lt 2GB) {
                    Log-Message "File size too small, download may be corrupted" -Error
                    Remove-Item $Destination -Force
                    continue
                }
                
                # Verify checksum
                if (-not (Verify-ISOChecksum -FilePath $Destination)) {
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
    
    # All mirrors failed
    Log-Message "All automatic download attempts failed" -Error
    
    $response = [System.Windows.Forms.MessageBox]::Show(
        "Automatic download failed. Would you like to:`n`n" +
        "- Download manually from your browser?`n" +
        "- Place the file at: $Destination`n" +
        "- Then run the installer again`n`n" +
        "Click Yes to open the $isoName download page, No to cancel",
        "Download Failed",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    
    if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
        if ($ubuntuRadio.Checked) {
            Start-Process "https://ubuntu.com/download/desktop"
            Log-Message "Please download Ubuntu 24.04.4 LTS (64-bit) and save it as:"
        } elseif ($kubuntuRadio.Checked) {
            Start-Process "https://kubuntu.org/getkubuntu/"
            Log-Message "Please download Kubuntu 24.04.4 LTS (64-bit) and save it as:"
        } elseif ($debianRadio.Checked) {
            Start-Process "https://www.debian.org/CD/live/"
            Log-Message "Please download Debian Live 13.3.0 KDE (amd64) and save it as:"
        } elseif ($fedoraRadio.Checked) {
            Start-Process "https://fedoraproject.org/kde/download/"
            Log-Message "Please download Fedora 43 KDE Plasma Desktop (x86_64) and save it as:"
        } else {
            Start-Process "https://linuxmint.com/edition.php?id=326"
            Log-Message "Please download Linux Mint 22.3 Cinnamon (64-bit) and save it as:"
        }
        Log-Message $Destination
        Log-Message "Then run the installer again"
    }
    
    return $false
}

function Start-Installation {
    if ($script:IsRunning) {
        return
    }
    
    $distroName = if ($ubuntuRadio.Checked) { "Ubuntu 24.04.4 LTS" } elseif ($kubuntuRadio.Checked) { "Kubuntu 24.04.4 LTS" } elseif ($debianRadio.Checked) { "Debian Live 13.3.0 KDE" } elseif ($fedoraRadio.Checked) { "Fedora 43 KDE" } else { "Linux Mint 22.3" }
    
    # Get Linux size
    $linuxSizeGB = $sizeNumeric.Value
    $totalNeededGB = $linuxSizeGB + $script:MinPartitionSizeGB
    
    # Quick space sanity check on C: disk before showing the plan
    # (The plan dialog itself validates whichever disk is selected)
    # We only block here if even the C: disk is clearly hopeless AND there
    # are no other disks the user could pick.
    $allOnlineDisks = Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' -and $_.Size -gt 10GB }
    $hasOtherDisks = ($allOnlineDisks | Where-Object { $_.Number -ne $script:CDriveInfo.DiskNumber }).Count -gt 0
    
    if (-not $hasOtherDisks -and $script:CDriveInfo.FreeGB -lt ($totalNeededGB + 10)) {
        # Check if there's enough unallocated space to compensate
        $disk = Get-Disk -Number $script:CDriveInfo.DiskNumber
        $partitions = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber | Sort-Object Offset
        $totalUnalloc = 0
        $previousEnd = [int64]0
        foreach ($part in $partitions) {
            $gap = $part.Offset - $previousEnd
            if ($gap -gt 1MB) { $totalUnalloc += $gap }
            $previousEnd = $part.Offset + $part.Size
        }
        $trailingGap = $disk.Size - $previousEnd
        if ($trailingGap -gt 1MB) { $totalUnalloc += $trailingGap }
        $totalUnallocGB = [math]::Round($totalUnalloc / 1GB, 2)
        
        if ($totalUnallocGB -lt $totalNeededGB) {
            Log-Message "Error: Not enough free space!" -Error
            Log-Message "Need: $($totalNeededGB + 10) GB (from C: free space or unallocated)" -Error
            Log-Message "C: free space: $($script:CDriveInfo.FreeGB) GB, Unallocated: $totalUnallocGB GB" -Error
            [System.Windows.Forms.MessageBox]::Show(
                "Not enough disk space available.`n`n" +
                "Needed: $totalNeededGB GB`n" +
                "C: drive free space: $($script:CDriveInfo.FreeGB) GB`n" +
                "Existing unallocated: $totalUnallocGB GB`n`n" +
                "Please free up space or reduce the Linux partition size.",
                "Insufficient Space",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }
    }
    
    # ========================================
    # SHOW DISK PLAN - user must approve
    # ========================================
    $planResult = Show-DiskPlan -DistroName $distroName -LinuxSizeGB $linuxSizeGB
    
    if (-not $planResult.Approved) {
        Log-Message "Installation cancelled by user at disk plan review."
        Set-Status "Ready to install"
        return
    }
    
    $selectedStrategy = $planResult.Strategy
    $targetDiskNumber = $planResult.TargetDiskNumber
    $isOtherDrive = ($selectedStrategy -eq "other_drive" -or $selectedStrategy -eq "other_drive_shrink")
    $otherDriveShrinkLetter = $planResult.ShrinkDriveLetter
    $otherDriveShrinkAmountGB = $planResult.ShrinkAmountGB
    Log-Message "Disk plan approved. Strategy: $selectedStrategy, Target disk: $targetDiskNumber"
    
    # Now lock the UI and proceed
    $script:IsRunning = $true
    $startButton.Enabled = $false
    $exitButton.Enabled = $false
    $sizeNumeric.Enabled = $false
    $deleteIsoCheck.Enabled = $false
    $autoRestartCheck.Enabled = $false
    $customRadio.Enabled = $false
    $browseButton.Enabled = $false
    $mintRadio.Enabled = $false
    $ubuntuRadio.Enabled = $false
    $kubuntuRadio.Enabled = $false
    $debianRadio.Enabled = $false
    $fedoraRadio.Enabled = $false
    
    try {
        # Determine ISO path
        if ($customRadio.Checked) {
            if (-not $script:CustomIsoPath -or -not (Test-Path $script:CustomIsoPath)) {
                Log-Message "Error: Please select a valid ISO file!" -Error
                return
            }
            $script:IsoPath = $script:CustomIsoPath
            Log-Message "Using custom ISO: $script:IsoPath"
            $isoInfo = Get-Item $script:IsoPath
            Log-Message "ISO file size: $([math]::Round($isoInfo.Length / 1GB, 2)) GB"
        } else {
            if ($ubuntuRadio.Checked) {
                $script:IsoPath = Join-Path $env:TEMP $script:UbuntuIsoFilename
                Log-Message "Selected distribution: Ubuntu 24.04.4 LTS"
            } elseif ($kubuntuRadio.Checked) {
                $script:IsoPath = Join-Path $env:TEMP $script:KubuntuIsoFilename
                Log-Message "Selected distribution: Kubuntu 24.04.4 LTS"
            } elseif ($debianRadio.Checked) {
                $script:IsoPath = Join-Path $env:TEMP $script:DebianIsoFilename
                Log-Message "Selected distribution: Debian Live 13.3.0 KDE"
            } elseif ($fedoraRadio.Checked) {
                $script:IsoPath = Join-Path $env:TEMP $script:FedoraIsoFilename
                Log-Message "Selected distribution: Fedora 43 KDE Plasma Desktop"
            } else {
                $script:IsoPath = Join-Path $env:TEMP "linuxmint-22.3-cinnamon-64bit.iso"
                Log-Message "Selected distribution: Linux Mint 22.3 Zena (Cinnamon)"
            }
        }
        
        # Check space (only if we're shrinking C:)
        if ($selectedStrategy -eq "shrink_all") {
            if ($script:CDriveInfo.FreeGB -lt ($totalNeededGB + 10)) {
                Log-Message "Error: Not enough free space on C: to shrink!" -Error
                Log-Message "Need: $($totalNeededGB + 10) GB free on C:" -Error
                Log-Message "Have: $($script:CDriveInfo.FreeGB) GB" -Error
                return
            }
        } elseif ($selectedStrategy -eq "use_free_boot") {
            if ($script:CDriveInfo.FreeGB -lt ($linuxSizeGB + 10)) {
                Log-Message "Error: Not enough free space on C: to shrink!" -Error
                Log-Message "Need: $($linuxSizeGB + 10) GB free on C:" -Error
                Log-Message "Have: $($script:CDriveInfo.FreeGB) GB" -Error
                return
            }
        } elseif ($selectedStrategy -eq "other_drive") {
            $otherDiskFreeGB = Get-DiskUnallocatedGB -DiskNumber $targetDiskNumber
            if ($otherDiskFreeGB -lt ($script:MinPartitionSizeGB + 1)) {
                Log-Message "Error: Not enough unallocated space on Disk $targetDiskNumber!" -Error
                Log-Message "Need: $($script:MinPartitionSizeGB + 1) GB, Have: $otherDiskFreeGB GB" -Error
                return
            }
        } elseif ($selectedStrategy -eq "other_drive_shrink") {
            if (-not $otherDriveShrinkLetter) {
                Log-Message "Error: No partition selected to shrink on Disk $targetDiskNumber!" -Error
                return
            }
            try {
                $shrinkVol = Get-Volume -DriveLetter $otherDriveShrinkLetter -ErrorAction Stop
                $shrinkFreeGB = [math]::Round($shrinkVol.SizeRemaining / 1GB, 2)
                if ($shrinkFreeGB -lt ($otherDriveShrinkAmountGB + 5)) {
                    Log-Message "Error: Not enough free space on ${otherDriveShrinkLetter}: to shrink!" -Error
                    Log-Message "Need: $($otherDriveShrinkAmountGB + 5) GB free, Have: $shrinkFreeGB GB" -Error
                    return
                }
            } catch {
                Log-Message "Error: Cannot access volume ${otherDriveShrinkLetter}: - $_" -Error
                return
            }
        }
        
        # Download ISO if needed
        if (-not $customRadio.Checked) {
            if (Test-Path $script:IsoPath) {
                Log-Message "Found existing ISO at: $script:IsoPath"
                
                try {
                    $fileInfo = Get-Item $script:IsoPath
                    $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
                    Log-Message "Existing ISO size: $fileSizeGB GB"
                    
                    if ($fileInfo.Length -lt 2GB) {
                        Log-Message "Existing ISO appears corrupted (too small)" -Error
                        Log-Message "Deleting corrupted file..." -Error
                        Remove-Item $script:IsoPath -Force
                        
                        Set-Status "Re-downloading $distroName ISO..."
                        if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                            Log-Message "Failed to download $distroName ISO!" -Error
                            return
                        }
                    } else {
                        if (-not (Verify-ISOChecksum -FilePath $script:IsoPath)) {
                            Log-Message "Existing ISO failed checksum verification" -Error
                            
                            Set-Status "Re-downloading $distroName ISO..."
                            if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                                Log-Message "Failed to download $distroName ISO!" -Error
                                return
                            }
                        } else {
                            if (-not $debianRadio.Checked -and -not $fedoraRadio.Checked) {
                                try {
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
                                        Set-Status "Re-downloading $distroName ISO..."
                                        if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                                            Log-Message "Failed to download $distroName ISO!" -Error
                                            return
                                        }
                                    } else {
                                        Log-Message "Installation cancelled by user" -Error
                                        return
                                    }
                                }
                            } else {
                                $hybridLabel = if ($debianRadio.Checked) { "Debian" } else { "Fedora" }
                                Log-Message "ISO mount test skipped ($hybridLabel hybrid ISO format)"
                            }
                        }
                    }
                }
                catch {
                    Log-Message "Error checking existing ISO: $_" -Error
                    return
                }
            } else {
                Set-Status "Downloading $distroName ISO..."
                if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                    Log-Message "Failed to download $distroName ISO!" -Error
                    return
                }
            }
        }
        
        # Shrink partition (skip if using all free space or targeting another drive with free space)
        if ($selectedStrategy -eq "other_drive_shrink") {
            # Shrink a partition on the other drive
            Set-Status "Shrinking ${otherDriveShrinkLetter}: partition on Disk $targetDiskNumber..."
            Log-Message "Shrinking ${otherDriveShrinkLetter}: partition by $otherDriveShrinkAmountGB GB..."
            Log-Message "This will create space for Linux: $linuxSizeGB GB and boot partition: $($script:MinPartitionSizeGB) GB..."
            
            try {
                $currentSize = (Get-Partition -DriveLetter $otherDriveShrinkLetter).Size
                $newSize = $currentSize - ($otherDriveShrinkAmountGB * 1GB)
                
                Resize-Partition -DriveLetter $otherDriveShrinkLetter -Size $newSize -ErrorAction Stop
                Log-Message "${otherDriveShrinkLetter}: partition shrunk successfully!"
            }
            catch {
                Log-Message "Trying diskpart method..."
                $sizeMB = [int]($otherDriveShrinkAmountGB * 1024)
                $diskpartScript = @"
select volume $otherDriveShrinkLetter
shrink desired=$sizeMB
exit
"@
                $scriptPath = Join-Path $env:TEMP "shrink_script.txt"
                $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
                
                $result = diskpart /s $scriptPath
                Remove-Item $scriptPath -Force
                
                if ($result -match "successfully") {
                    Log-Message "${otherDriveShrinkLetter}: partition shrunk successfully!"
                } else {
                    Log-Message "Failed to shrink ${otherDriveShrinkLetter}: partition!" -Error
                    Log-Message "You may need to: 1) Run disk cleanup 2) Defragment the drive 3) Reboot" -Error
                    return
                }
            }
            
            Start-Sleep -Seconds 5
        } elseif ($selectedStrategy -ne "use_free_all" -and -not $isOtherDrive) {
            $shrinkAmountGB = if ($selectedStrategy -eq "use_free_boot") { $linuxSizeGB } else { $totalNeededGB }
            
            Set-Status "Shrinking C: partition..."
            Log-Message "Shrinking C: partition by $shrinkAmountGB GB..."
            
            if ($selectedStrategy -eq "shrink_all") {
                $bootSizeGB = $script:MinPartitionSizeGB
                Log-Message "This will create space for Linux: $linuxSizeGB GB and boot partition: $bootSizeGB GB..."
            } else {
                Log-Message "This will create $linuxSizeGB GB of space for Linux installation..."
                Log-Message "The 7 GB boot partition will use existing unallocated space."
            }
            
            try {
                $currentSize = (Get-Partition -DriveLetter C).Size
                $newSize = $currentSize - ($shrinkAmountGB * 1GB)
                
                Resize-Partition -DriveLetter C -Size $newSize -ErrorAction Stop
                Log-Message "C: partition shrunk successfully!"
            }
            catch {
                Log-Message "Trying diskpart method..."
                $sizeMB = [int]($shrinkAmountGB * 1024)
                $diskpartScript = @"
select volume c
shrink desired=$sizeMB
exit
"@
                $scriptPath = Join-Path $env:TEMP "shrink_script.txt"
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
            
            Start-Sleep -Seconds 5
        } else {
            if ($isOtherDrive) {
                Log-Message "Skipping C: partition shrink - installing to a separate disk (Disk $targetDiskNumber)."
            } else {
                Log-Message "Skipping C: partition shrink - using existing unallocated space."
            }
        }
        
        # Create boot partition
        Set-Status "Creating boot partition..."
        Log-Message "Creating $script:MinPartitionSizeGB GB boot partition on Disk $targetDiskNumber..."
        
        try {
            Start-Sleep -Seconds 2
            $disk = Get-Disk -Number $targetDiskNumber
            $partitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset
            
            # For the C: disk, position relative to C:. For other disks, use free space.
            if (-not $isOtherDrive) {
                $cPartition = Get-Partition -DriveLetter C
                $cPartitionEnd = $cPartition.Offset + $cPartition.Size
                $anchorEnd = $cPartitionEnd
            } elseif ($selectedStrategy -eq "other_drive_shrink" -and $otherDriveShrinkLetter) {
                # Anchor relative to the partition we just shrunk
                $shrunkPartition = Get-Partition -DriveLetter $otherDriveShrinkLetter
                $anchorEnd = $shrunkPartition.Offset + $shrunkPartition.Size
            } else {
                # For other drives, anchor after the last existing partition
                if ($partitions -and $partitions.Count -gt 0) {
                    $lastPart = $partitions | Sort-Object Offset | Select-Object -Last 1
                    $anchorEnd = $lastPart.Offset + $lastPart.Size
                } else {
                    $anchorEnd = [int64](1MB)  # Start near beginning for empty disks
                }
            }
            
            # ── Scan ALL unallocated gaps on the disk ────────────────────────
            # Instead of only looking at space immediately after the anchor,
            # enumerate every gap between (and after) partitions, then pick
            # the best one that is large enough for the boot partition.
            $gaps = @()
            $sortedParts = $partitions | Sort-Object Offset
            $prevEnd = [int64]0
            
            foreach ($part in $sortedParts) {
                $gapSize = $part.Offset - $prevEnd
                if ($gapSize -gt 1MB) {
                    $gaps += [PSCustomObject]@{
                        Start = $prevEnd
                        End   = $part.Offset
                        Size  = $gapSize
                    }
                }
                $prevEnd = $part.Offset + $part.Size
            }
            # Trailing space after the last partition
            $trailingGap = $disk.Size - $prevEnd
            if ($trailingGap -gt 1MB) {
                $gaps += [PSCustomObject]@{
                    Start = $prevEnd
                    End   = $disk.Size
                    Size  = $trailingGap
                }
            }
            
            $bootPartitionSize = [int64]($script:MinPartitionSizeGB * 1GB)
            $alignmentSize = [int64](1MB)
            $bufferSize = [int64](16MB)
            $minGapRequired = $bootPartitionSize + $bufferSize + $alignmentSize
            
            # Log all gaps found
            Log-Message "Scanning disk for unallocated gaps..."
            foreach ($gap in $gaps) {
                $gapGB = [math]::Round($gap.Size / 1GB, 2)
                $gapStartGB = [math]::Round($gap.Start / 1GB, 2)
                Log-Message "  Gap at $gapStartGB GB: $gapGB GB"
            }
            
            # Filter to gaps that are large enough for the boot partition
            $usableGaps = $gaps | Where-Object { $_.Size -ge $minGapRequired }
            
            if (-not $usableGaps) {
                throw "No unallocated gap large enough for the $script:MinPartitionSizeGB GB boot partition"
            }
            
            # Prefer: (1) the gap right after the anchor if it's big enough,
            #          (2) otherwise the largest usable gap on the disk.
            $anchorGap = $usableGaps | Where-Object {
                $_.Start -ge ($anchorEnd - 1MB) -and $_.Start -le ($anchorEnd + 1MB)
            } | Select-Object -First 1
            
            $chosenGap = if ($anchorGap) { $anchorGap } 
                         else { $usableGaps | Sort-Object Size -Descending | Select-Object -First 1 }
            
            $chosenGapGB = [math]::Round($chosenGap.Size / 1GB, 2)
            $chosenStartGB = [math]::Round($chosenGap.Start / 1GB, 2)
            Log-Message "Selected gap for boot partition: $chosenGapGB GB starting at $chosenStartGB GB"
            
            # Place the boot partition at the END of the chosen gap so the
            # remaining space before it stays contiguous for the Linux install.
            $bootPartitionEndOffset = $chosenGap.End - $bufferSize
            $bootPartitionOffset = $bootPartitionEndOffset - $bootPartitionSize
            $bootPartitionOffset = [int64]([Math]::Floor($bootPartitionOffset / $alignmentSize)) * $alignmentSize
            
            if ($bootPartitionOffset -lt ($chosenGap.Start + $alignmentSize)) {
                throw "Selected gap ($chosenGapGB GB) is too small after alignment for the boot partition"
            }
            
            $linuxSpace = $bootPartitionOffset - $chosenGap.Start
            $linuxSpaceGB = [math]::Round($linuxSpace / 1GB, 2)
            
            Log-Message "Unallocated space starts at: $chosenStartGB GB"
            Log-Message "Boot partition will start at: $([math]::Round($bootPartitionOffset / 1GB, 2)) GB"
            Log-Message "Gap ends at: $([math]::Round($chosenGap.End / 1GB, 2)) GB"
            Log-Message "Linux will have $linuxSpaceGB GB of unallocated space"
            
            Log-Message "Creating boot partition..."
            
            $bootPartitionSize = [int64]($script:MinPartitionSizeGB * 1GB)
            $offsetMB = [int64]([Math]::Floor($bootPartitionOffset / 1MB))
            $sizeMB = [int64]($script:MinPartitionSizeGB * 1024)
            
            if ($offsetMB -lt 0 -or $bootPartitionOffset -gt $disk.Size) {
                throw "Invalid offset calculated: $offsetMB MB (from $bootPartitionOffset bytes)"
            }
            
            Log-Message "Attempting to create partition at offset: $([math]::Round($bootPartitionOffset / 1GB, 2)) GB - $offsetMB MB"
            
            $partitionCreated = $false
            $newPartition = $null
            
            try {
                Log-Message "Attempting PowerShell method with specific offset..."
                $newPartition = New-Partition -DiskNumber $targetDiskNumber `
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
                
                $attempts = @(
                    @{Offset = $offsetMB; Description = "Calculated position"},
                    @{Offset = [int64]($offsetMB - 1024); Description = "1GB before calculated position"},
                    @{Offset = [int64]($offsetMB - 2048); Description = "2GB before calculated position"},
                    @{Offset = [int64]($offsetMB - 5120); Description = "5GB before calculated position"}
                )
                
                $attempts = $attempts | Where-Object { $_.Offset -gt 0 }
                
                foreach ($attempt in $attempts) {
                    Log-Message "Attempt: $($attempt.Description)"
                    Log-Message "Trying offset: $([math]::Round($attempt.Offset * 1MB / 1GB, 2)) GB"
                    
                    $diskpartScript = @"
select disk $targetDiskNumber
create partition primary offset=$($attempt.Offset) size=$sizeMB
assign
exit
"@
                    $scriptPath = Join-Path $env:TEMP "create_boot_partition.txt"
                    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
                    
                    $result = & diskpart /s $scriptPath 2>&1
                    Remove-Item $scriptPath -Force
                    
                    $resultString = $result -join "`n"
                    
                    if ($resultString -match "successfully created" -or $resultString -match "DiskPart successfully created") {
                        Log-Message "Success! Boot partition created at offset $([math]::Round($attempt.Offset * 1MB / 1GB, 2)) GB"
                        $partitionCreated = $true
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
            
            if (-not $partitionCreated -and -not $isOtherDrive) {
                Log-Message "Offset-based creation failed. Trying alternative approach..."
                
                $currentPartitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset
                $cPartition = $currentPartitions | Where-Object { $_.DriveLetter -eq 'C' }
                $cEndOffset = $cPartition.Offset + $cPartition.Size
                
                $recoveryPartition = $currentPartitions | Where-Object { 
                    $_.Type -eq "Recovery" -or $_.GptType -match "de94bba4"
                } | Sort-Object Offset | Select-Object -First 1
                
                if ($recoveryPartition) {
                    $gapSize = $recoveryPartition.Offset - $cEndOffset
                    $gapSizeGB = [math]::Round($gapSize / 1GB, 2)
                    Log-Message "Gap between C: and Recovery: $gapSizeGB GB"
                    
                    $fillerSize = [int64]($gapSize - ($script:MinPartitionSizeGB * 1GB) - (1GB))
                    $fillerSizeGB = [math]::Round($fillerSize / 1GB, 2)
                    
                    if ($fillerSize -gt 0) {
                        Log-Message "Attempting workaround: Creating filler partition of $fillerSizeGB GB"
                        
                        try {
                            $fillerPartition = New-Partition -DiskNumber $targetDiskNumber `
                                -Size $fillerSize `
                                -ErrorAction Stop
                            
                            Log-Message "Filler partition created. Now creating boot partition..."
                            
                            $bootPartition = New-Partition -DiskNumber $targetDiskNumber `
                                -Size ($script:MinPartitionSizeGB * 1GB) `
                                -AssignDriveLetter `
                                -ErrorAction Stop
                            
                            Log-Message "Removing filler partition..."
                            Remove-Partition -DiskNumber $targetDiskNumber `
                                -PartitionNumber $fillerPartition.PartitionNumber `
                                -Confirm:$false `
                                -ErrorAction Stop
                            
                            Log-Message "Filler partition removed. Boot partition should now be at end."
                            $partitionCreated = $true
                            $newPartition = $bootPartition
                            $driveLetter = $bootPartition.DriveLetter
                            
                            if (-not $driveLetter) {
                                Start-Sleep -Seconds 3
                                $bootPartition = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $bootPartition.PartitionNumber
                                $driveLetter = $bootPartition.DriveLetter
                            }
                        }
                        catch {
                            Log-Message "Workaround failed: $_" -Error
                        }
                    }
                }
            }
            
            if (-not $partitionCreated) {
                Log-Message "All offset methods failed. Creating partition without specific offset..."
                try {
                    $newPartition = New-Partition -DiskNumber $targetDiskNumber `
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
                Start-Sleep -Seconds 3
                
                $targetSize = [int64]($script:MinPartitionSizeGB * 1GB)
                $tolerance = [int64](100MB)
                
                $newPartitions = Get-Partition -DiskNumber $targetDiskNumber | 
                    Where-Object { [Math]::Abs($_.Size - $targetSize) -lt $tolerance }
                
                $bootPartition = $newPartitions | Sort-Object Offset -Descending | Select-Object -First 1
                
                if ($bootPartition) {
                    $driveLetter = $bootPartition.DriveLetter
                    
                    if (-not $driveLetter) {
                        $bootPartition | Add-PartitionAccessPath -AssignDriveLetter
                        Start-Sleep -Seconds 2
                        $bootPartition = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $bootPartition.PartitionNumber
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
            
            $volumeLabel = "LINUX_LIVE"
            
            Format-Volume -DriveLetter $driveLetter `
                -FileSystem FAT32 `
                -NewFileSystemLabel $volumeLabel `
                -Confirm:$false `
                -ErrorAction Stop
            
            Log-Message "Boot partition created and assigned to ${driveLetter}:"
            $script:NewDrive = "${driveLetter}:"
            $script:VolumeLabel = $volumeLabel
            
            Log-Message ""
            Log-Message "=== Final Disk Layout (Disk $targetDiskNumber) ==="
            $finalPartitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset
            
            $previousEnd = [int64]0
            foreach ($part in $finalPartitions) {
                $sizeGB = [math]::Round($part.Size / 1GB, 2)
                $offsetGB = [math]::Round($part.Offset / 1GB, 2)
                $endGB = [math]::Round(($part.Offset + $part.Size) / 1GB, 2)
                
                if ($part.Offset -gt ($previousEnd + 1MB)) {
                    $gapSize = [math]::Round(($part.Offset - $previousEnd) / 1GB, 2)
                    if ($gapSize -gt 0.1) {
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
            if (-not (Test-Path $script:IsoPath)) {
                Log-Message "ISO file not found at: $script:IsoPath" -Error
                return
            }
            
            $mountResult = Mount-DiskImage -ImagePath $script:IsoPath -PassThru -ErrorAction Stop
            Start-Sleep -Seconds 2
            
            $isoVolume = Get-Volume -DiskImage $mountResult -ErrorAction Stop | Select-Object -First 1
            
            if (-not $isoVolume) {
                Log-Message "Failed to get volume information from mounted ISO" -Error
                Dismount-DiskImage -ImagePath $script:IsoPath -ErrorAction SilentlyContinue
                return
            }
            
            $sourceDrive = "$($isoVolume.DriveLetter):"
            Log-Message "ISO mounted at $sourceDrive"
            
            if (-not $customRadio.Checked) {
                $validationFile = if ($debianRadio.Checked) {
                    "$sourceDrive\live\vmlinuz"
                } elseif ($fedoraRadio.Checked) {
                    "$sourceDrive\LiveOS\squashfs.img"
                } else {
                    "$sourceDrive\casper\vmlinuz"
                }
                
                if (-not (Test-Path $validationFile)) {
                    Log-Message "Warning: ISO may not be a valid $distroName image (missing expected files)" -Error
                    
                    $response = [System.Windows.Forms.MessageBox]::Show(
                        "The ISO doesn't appear to be a valid $distroName image. Continue anyway?",
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
            
            $response = [System.Windows.Forms.MessageBox]::Show(
                "Failed to mount the ISO file. It may be corrupted. Would you like to delete it and re-download?",
                "Mount Failed",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            
            if ($response -eq [System.Windows.Forms.DialogResult]::Yes -and -not $customRadio.Checked) {
                try {
                    Remove-Item $script:IsoPath -Force
                    Log-Message "Deleted corrupted ISO"
                    
                    Set-Status "Re-downloading $distroName ISO..."
                    if (Download-LinuxISO -Destination $script:IsoPath) {
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
        Log-Message "Copying $distroName files to $script:NewDrive..."
        Log-Message "This may take 10-20 minutes..."
        
        try {
            $robocopyArgs = @(
                $sourceDrive,
                $script:NewDrive,
                "/E",
                "/R:3",
                "/W:5",
                "/NP",
                "/NFL",
                "/NDL",
                "/ETA"
            )
            
            $result = robocopy @robocopyArgs
            
            if ($LASTEXITCODE -ge 8) {
                Log-Message "Failed to copy files! Exit code: $LASTEXITCODE" -Error
                return
            }
            
            Log-Message "Files copied successfully!"
            
            Log-Message "Removing read-only attributes..."
            attrib -R ($script:NewDrive + "\*.*") /S /D
        }
        catch {
            Log-Message "Error during file copy: $_" -Error
            return
        }
        finally {
            Dismount-DiskImage -ImagePath $script:IsoPath
        }
        
        # Fedora-specific: fix volume label in GRUB and isolinux configs
        if ($fedoraRadio.Checked) {
            Set-Status "Fixing Fedora boot labels..."
            Log-Message "Fixing Fedora volume label references in boot configs..."
            
            $fedoraLabel = $script:VolumeLabel
            
            $bootConfigFiles = @()
            $searchPaths = @(
                (Join-Path $script:NewDrive "EFI\BOOT\grub.cfg"),
                (Join-Path $script:NewDrive "EFI\BOOT\BOOT.conf"),
                (Join-Path $script:NewDrive "boot\grub2\grub.cfg"),
                (Join-Path $script:NewDrive "boot\grub\grub.cfg"),
                (Join-Path $script:NewDrive "isolinux\isolinux.cfg"),
                (Join-Path $script:NewDrive "isolinux\grub.conf"),
                (Join-Path $script:NewDrive "syslinux\syslinux.cfg")
            )
            
            foreach ($cfgPath in $searchPaths) {
                if (Test-Path $cfgPath) {
                    $bootConfigFiles += $cfgPath
                }
            }
            
            if ($bootConfigFiles.Count -eq 0) {
                Log-Message "Warning: No boot config files found to patch" -Error
            } else {
                $patchedCount = 0
                foreach ($cfgFile in $bootConfigFiles) {
                    try {
                        $content = Get-Content $cfgFile -Raw -ErrorAction Stop
                        $originalContent = $content
                        
                        $content = $content -replace '(root=live:(?:CD)?LABEL=)([^\s\\]+)', "`$1$fedoraLabel"
                        $content = $content -replace '(set isolabel=)([^\s]+)', "`$1$fedoraLabel"
                        $content = $content -replace '(CDLABEL=)([^\s\\]+)', "`$1$fedoraLabel"
                        
                        if ($content -ne $originalContent) {
                            Set-Content -Path $cfgFile -Value $content -Encoding UTF8 -Force
                            Log-Message "  Patched: $(Split-Path -Leaf $cfgFile)"
                            $patchedCount++
                        } else {
                            Log-Message "  No label references in: $(Split-Path -Leaf $cfgFile)"
                        }
                    }
                    catch {
                        Log-Message "  Warning: Could not patch $($cfgFile): $_" -Error
                    }
                }
                
                if ($patchedCount -gt 0) {
                    Log-Message "Patched $patchedCount boot config file(s) with label '$fedoraLabel'"
                } else {
                    Log-Message "Warning: No LABEL references found to patch. Fedora may not boot correctly." -Error
                    Log-Message "You may need to manually edit EFI\BOOT\grub.cfg and replace the LABEL= value with '$fedoraLabel'" -Error
                }
            }
        }
        
        # Create boot configuration
        Set-Status "Creating boot configuration..."
        Log-Message "Creating boot configuration..."
        
        $efiPath = $script:NewDrive + "\EFI\BOOT"
        if (-not (Test-Path $efiPath)) {
            New-Item -Path $efiPath -ItemType Directory -Force
        }
        
        if ($autoRestartCheck.Checked) {
            Log-Message "Configuring UEFI boot priority..."
            Set-Status "Configuring UEFI boot priority..."
            
            try {
                $bcdeditOutput = bcdedit /enum firmware 2>&1
                $lines = $bcdeditOutput
                
                $bootEntries = @()
                $currentEntry = $null
                
                foreach ($line in $lines) {
                    if ($line -match '^Firmware Application \(') {
                        if ($currentEntry) {
                            $bootEntries += $currentEntry
                        }
                        $currentEntry = @{}
                    }
                    elseif ($line -match '^identifier\s+(.+)$') {
                        if ($currentEntry) {
                            $currentEntry.ID = $matches[1].Trim()
                        }
                    }
                    elseif ($line -match '^description\s+(.+)$') {
                        if ($currentEntry) {
                            $currentEntry.Description = $matches[1].Trim()
                        }
                    }
                }
                if ($currentEntry) {
                    $bootEntries += $currentEntry
                }
                
                Log-Message "Found $($bootEntries.Count) firmware boot entries:"
                foreach ($entry in $bootEntries) {
                    Log-Message "  $($entry.Description) [$($entry.ID)]"
                }
                
                $distroKeyword = if ($fedoraRadio.Checked) { "Fedora" }
                    elseif ($ubuntuRadio.Checked) { "Ubuntu" }
                    elseif ($kubuntuRadio.Checked) { "Kubuntu" }
                    elseif ($debianRadio.Checked) { "Debian" }
                    elseif ($mintRadio.Checked) { "Mint" }
                    else { $distroName.Split(' ')[0] }
                
                $targetEntry = $null
                
                $targetEntry = $bootEntries | Where-Object { $_.Description -like "*$distroKeyword*" } | Select-Object -First 1
                if ($targetEntry) {
                    Log-Message "Found existing boot entry for '$distroKeyword'"
                }
                
                if (-not $targetEntry) {
                    $targetEntry = $bootEntries | Where-Object { $_.Description -like '*UEFI OS*' } | Select-Object -First 1
                    if ($targetEntry) {
                        Log-Message "Found generic 'UEFI OS' boot entry"
                    }
                }
                
                if ($targetEntry) {
                    Log-Message "Setting boot priority to: $($targetEntry.Description) [$($targetEntry.ID)]"
                    
                    $process = Start-Process -FilePath "bcdedit.exe" `
                        -ArgumentList "/set", "{fwbootmgr}", "default", $targetEntry.ID `
                        -Wait -PassThru -NoNewWindow
                    
                    if ($process.ExitCode -eq 0) {
                        Log-Message "UEFI boot priority set successfully!"
                    } else {
                        Log-Message "bcdedit /set default returned exit code $($process.ExitCode)" -Error
                    }
                } else {
                    Log-Message "No existing boot entry found for $distroName"
                    Log-Message "Creating new UEFI firmware boot entry..."
                    
                    $driveLetter = $script:NewDrive.TrimEnd(':')
                    $bootCreated = $false
                    
                    try {
                        Log-Message "Attempting bcdedit /copy method..."
                        $copyOutput = bcdedit /copy "{bootmgr}" /d "$distroName" 2>&1
                        $copyOutputStr = $copyOutput -join " "
                        
                        if ($copyOutputStr -match '\{[0-9a-fA-F-]+\}') {
                            $newGuid = $matches[0]
                            Log-Message "Created new entry: $newGuid"
                            
                            $inheritedProps = @("default", "displayorder", "toolsdisplayorder", "timeout", "resumeobject", "inherit", "locale")
                            foreach ($prop in $inheritedProps) {
                                Start-Process "bcdedit.exe" -ArgumentList "/deletevalue", $newGuid, $prop -Wait -NoNewWindow -ErrorAction SilentlyContinue 2>$null | Out-Null
                            }
                            Log-Message "Cleaned inherited Windows Boot Manager properties"
                            
                            $r1 = Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "device", "partition=$script:NewDrive" -Wait -PassThru -NoNewWindow
                            $r2 = Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "path", "\EFI\BOOT\BOOTx64.EFI" -Wait -PassThru -NoNewWindow
                            Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "description", "$distroName" -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
                            $r3 = Start-Process "bcdedit.exe" -ArgumentList "/set", "{fwbootmgr}", "displayorder", $newGuid, "/addfirst" -Wait -PassThru -NoNewWindow
                            $r4 = Start-Process "bcdedit.exe" -ArgumentList "/set", "{fwbootmgr}", "default", $newGuid -Wait -PassThru -NoNewWindow
                            
                            if ($r1.ExitCode -eq 0 -and $r2.ExitCode -eq 0 -and $r3.ExitCode -eq 0 -and $r4.ExitCode -eq 0) {
                                Log-Message "UEFI boot entry created and set as default!"
                                $bootCreated = $true
                            } else {
                                Log-Message "Some bcdedit commands failed (exit codes: set device=$($r1.ExitCode), set path=$($r2.ExitCode), displayorder=$($r3.ExitCode), default=$($r4.ExitCode))" -Error
                                Start-Process "bcdedit.exe" -ArgumentList "/delete", $newGuid -Wait -NoNewWindow -ErrorAction SilentlyContinue
                            }
                        } else {
                            Log-Message "bcdedit /copy did not return a GUID: $copyOutputStr"
                        }
                    }
                    catch {
                        Log-Message "bcdedit /copy method failed: $_"
                    }
                    
                    if (-not $bootCreated) {
                        try {
                            Log-Message "Attempting bcdedit /create method..."
                            $createOutput = bcdedit /create /d "$distroName" /application BOOTSECTOR 2>&1
                            $createOutputStr = $createOutput -join " "
                            
                            if ($createOutputStr -match '\{[0-9a-fA-F-]+\}') {
                                $newGuid = $matches[0]
                                Log-Message "Created entry: $newGuid"
                                
                                Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "device", "partition=$script:NewDrive" -Wait -PassThru -NoNewWindow
                                Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "path", "\EFI\BOOT\BOOTx64.EFI" -Wait -PassThru -NoNewWindow
                                Start-Process "bcdedit.exe" -ArgumentList "/set", "{fwbootmgr}", "displayorder", $newGuid, "/addfirst" -Wait -PassThru -NoNewWindow
                                Start-Process "bcdedit.exe" -ArgumentList "/set", "{fwbootmgr}", "default", $newGuid -Wait -PassThru -NoNewWindow
                                
                                Log-Message "UEFI boot entry created via /create method"
                                $bootCreated = $true
                            } else {
                                Log-Message "bcdedit /create did not return a GUID: $createOutputStr"
                            }
                        }
                        catch {
                            Log-Message "bcdedit /create method failed: $_"
                        }
                    }
                    
                    if (-not $bootCreated) {
                        Log-Message "Could not create UEFI boot entry automatically" -Error
                        Log-Message "You will need to set boot priority manually in UEFI/BIOS settings" -Error
                        Log-Message "Or use the one-time boot menu (usually F12) to select the $distroName partition" -Error
                    }
                }
            }
            catch {
                Log-Message "Error configuring UEFI boot: $_" -Error
                Log-Message "You may need to set boot priority manually in UEFI/BIOS settings" -Error
            }
        }
        
        # Create boot instructions
        $instructions = @"
UEFI Boot Setup Instructions for $distroName
========================================================

Your $distroName bootable partition has been created successfully!

Disk Layout (Disk $targetDiskNumber):
- Boot Drive: $script:NewDrive (7 GB, FAT32, labelled LINUX_LIVE)
- Disk Number: $targetDiskNumber
"@
        if ($isOtherDrive) {
            $instructions += @"

Note: Linux was installed to a separate disk (Disk $targetDiskNumber),
NOT the Windows system disk. The C: drive was not modified.

"@
        } else {
            $instructions += @"

- Windows C: drive (shrunk)
- Unallocated space: $linuxSizeGB GB (for Linux installation)

Important: The disk now has unallocated space that the $distroName
installer will automatically detect and use.

"@
        }

        if ($autoRestartCheck.Checked) {
            $instructions += @"

AUTOMATIC BOOT CONFIGURATION ENABLED:
====================================
UEFI boot priority has been configured. The system will restart
and boot directly into $distroName.
You can then proceed with the installation.

If automatic configuration fails, follow the manual steps below.

"@
        }

        $instructions += @"

MANUAL BOOT CONFIGURATION (if needed):
=======================================

To boot ${distroName}:

1. Restart your computer

2. Access UEFI/BIOS settings:
   - During startup, press the BIOS key (usually F2, F10, F12, DEL, or ESC)
   - The exact key depends on your motherboard manufacturer

3. In UEFI settings:
   - Look for "Boot" or "Boot Order" section
   - Find the $distroName entry (may appear as "UEFI: $script:NewDrive LINUXBOOT")
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
  \EFI\BOOT\BOOTx64.EFI on the boot partition
- If the installer doesn't see the unallocated space, use the manual
  partitioning option and create your partitions in the free space
"@
        
        $instructions | Out-File -FilePath ($script:NewDrive + "\UEFI_BOOT_INSTRUCTIONS.txt") -Encoding UTF8
        $instructions | Out-File -FilePath (Join-Path $env:USERPROFILE "Desktop\Linux_Boot_Instructions.txt") -Encoding UTF8
        
        # Success
        Log-Message "====================================="
        Log-Message "Installation Complete!"
        Log-Message "====================================="
        Log-Message "$distroName boot partition created at drive $script:NewDrive"
        if ($customRadio.Checked) {
            Log-Message "ISO used: $(Split-Path -Leaf $script:CustomIsoPath)"
        }
        Log-Message ""
        Log-Message "*** DISK LAYOUT ***"
        $finalPartitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset
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
            Log-Message "UEFI boot priority has been configured."
            Log-Message "The system will restart in 30 seconds!"
            Log-Message "After restart, the system will boot into $distroName"
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
        Log-Message ("- " + $script:NewDrive + "\UEFI_BOOT_INSTRUCTIONS.txt")
        Log-Message "- Desktop\Linux_Boot_Instructions.txt"
        
        Set-Status "Installation complete!"
        
        # Delete ISO if requested
        if ($deleteIsoCheck.Checked -and -not $customRadio.Checked) {
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
            
            $countdownForm = New-Object System.Windows.Forms.Form
            $countdownForm.Text = "System Restart"
            $countdownForm.Size = New-Object System.Drawing.Size(420, 210)
            $countdownForm.StartPosition = "CenterScreen"
            $countdownForm.FormBorderStyle = "FixedDialog"
            $countdownForm.MaximizeBox = $false
            $countdownForm.MinimizeBox = $false
            
            $countdownLabel = New-Object System.Windows.Forms.Label
            $countdownLabel.Text = "System will restart in 30 seconds...`n`nUEFI boot priority has been configured.`nThe system will boot directly into $distroName."
            $countdownLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $countdownLabel.Location = New-Object System.Drawing.Point(20, 20)
            $countdownLabel.Size = New-Object System.Drawing.Size(380, 90)
            $countdownLabel.TextAlign = "MiddleCenter"
            $countdownForm.Controls.Add($countdownLabel)
            
            $cancelButton = New-Object System.Windows.Forms.Button
            $cancelButton.Text = "Cancel Restart"
            $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $cancelButton.Location = New-Object System.Drawing.Point(135, 120)
            $cancelButton.Size = New-Object System.Drawing.Size(150, 35)
            $countdownForm.Controls.Add($cancelButton)
            
            $script:CancelRestart = $false
            $cancelButton.Add_Click({
                $script:CancelRestart = $true
                $countdownForm.Close()
            })
            
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 1000
            $script:CountdownSeconds = 30
            
            $timer.Add_Tick({
                $script:CountdownSeconds--
                $countdownLabel.Text = "System will restart in $script:CountdownSeconds seconds...`n`nUEFI boot priority has been configured.`nThe system will boot directly into $distroName."
                
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
        $customRadio.Enabled = $true
        $browseButton.Enabled = $true
        $mintRadio.Enabled = $true
        $ubuntuRadio.Enabled = $true
        $kubuntuRadio.Enabled = $true
        $debianRadio.Enabled = $true
        $fedoraRadio.Enabled = $true
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

# Event handlers
$customRadio.Add_CheckedChanged({
    if ($customRadio.Checked) {
        $customIsoTextbox.Enabled = $true
        $browseButton.Enabled = $true
    } else {
        $customIsoTextbox.Enabled = $false
        $browseButton.Enabled = $false
    }
})

$browseButton.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Select Linux ISO File"
    $openFileDialog.Filter = "ISO Files (*.iso)|*.iso|All Files (*.*)|*.*"
    $openFileDialog.FilterIndex = 1
    $openFileDialog.RestoreDirectory = $true
    
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:CustomIsoPath = $openFileDialog.FileName
        $customIsoTextbox.Text = $script:CustomIsoPath
        
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
