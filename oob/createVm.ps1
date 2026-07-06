# ==========================================
# CONFIGURATION
# ==========================================
$TemplateVHDX  = "E:\Vms\HyperVVMTemplateT01\Virtual Hard Disks\HyperVVMTemplateT01.vhdx"
$VMStorageDir  = "E:\Vms"
$SwitchName    = "extDefaultSwitch" # Your Hyper-V Switch

# New VM details (Change these when running the script)
$VMName        = "prod-web-04" 
$Memory        = 2GB
$ProcessorCount = 2

# ==========================================
# 1. SETUP PATHS & CLONE MASTER DISK
# ==========================================
$NewVMDir     = Join-Path $VMStorageDir $VMName
$NewVHDX      = Join-Path $NewVMDir "$VMName.vhdx"
$CloudInitVHD = Join-Path $NewVMDir "cloudinit-data.vhdx"

# Create VM directory and copy template disk
New-Item -ItemType Directory -Path $NewVMDir -Force | Out-Null

# If a stale cloud-init VHD file exists from a failed run, delete it manually
if (Test-Path $CloudInitVHD) { Remove-Item $CloudInitVHD -Force }
Copy-Item -Path $TemplateVHDX -Destination $NewVHDX

# ==========================================
# 2. GENERATE CLOUD-INIT VHDX NATIVELY
# ==========================================
Write-Host "Creating cloud-init metadata disk..." -ForegroundColor Cyan

# 1. Create a 100MB VHDX file (Increased from 20MB to satisfy FAT32 constraints)
$VHDLayout = New-VHD -Path $CloudInitVHD -SizeBytes 100MB -Dynamic

# 2. Mount it to the host system temporarily
$Disk = Mount-VHD -Path $CloudInitVHD -Passthru

# 3. Initialize, partition, and format as FAT32 labeled 'cidata'
$Disk | Initialize-Disk -PartitionStyle MBR -Passthru |
        New-Partition -UseMaximumSize -AssignDriveLetter |
        Format-Volume -FileSystem FAT32 -NewFileSystemLabel "cidata" -Force | Out-Null

# 4. Get the temporary drive letter assigned to the VHDX
$DriveLetter = (Get-Disk -Number $Disk.Number | Get-Partition | Where-Object DriveLetter).DriveLetter
$DrivePath   = "$($DriveLetter):\"

# 5. Write the required cloud-init configurations to the drive
$MetaDataContent = "local-hostname: $VMName`ninstance-id: $([guid]::NewGuid().Guid)"
$UserDataContent = "#cloud-config`nhostname: $VMName`nmanage_etc_hosts: true"

Set-Content -Path (Join-Path $DrivePath "meta-data") -Value $MetaDataContent -Encoding Ascii
Set-Content -Path (Join-Path $DrivePath "user-data") -Value $UserDataContent -Encoding Ascii

# 6. Unmount the VHDX so Hyper-V can take exclusive control of it
Dismount-VHD -Path $CloudInitVHD

# ==========================================
# 3. PROVISION HYPER-V VM
# ==========================================
Write-Host "Provisioning Hyper-V container..." -ForegroundColor Cyan

# Create the virtual machine
$VM = New-VM -Name $VMName -MemoryStartupBytes $Memory -Generation 1 -Path $VMStorageDir -SwitchName $SwitchName
Set-VM -Name $VMName -ProcessorCount $ProcessorCount

# Attach the main Operating System VHDX
Add-VMHardDiskDrive -VMName $VMName -Path $NewVHDX

# Attach the cloud-init metadata disk as a secondary drive
Add-VMHardDiskDrive -VMName $VMName -Path $CloudInitVHD

# Enable Hyper-V Guest Services
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"

# ==========================================
# 4. LAUNCH
# ==========================================
Start-VM -VMName $VMName
Write-Host "Successfully deployed and booted '$VMName'!" -ForegroundColor Green