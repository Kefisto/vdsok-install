#!/bin/bash

#
# windows specific functions
#
# (c) 2026, VDSok
#

WIN_INSTALL_STEPS=10

generate_config_windows() {
  debug "# Windows: generating disk configuration"

  if ((UEFI == 1)); then
    win_partition_disk_gpt "$DRIVE1" || return 1
  else
    win_partition_disk_mbr "$DRIVE1" || return 1
  fi

  if [[ "$SWRAID" == "1" ]] && [[ -n "$DRIVE2" ]]; then
    debug "# Windows: preparing mirror disk $DRIVE2"
    if ((UEFI == 1)); then
      win_partition_disk_gpt "$DRIVE2" || return 1
    else
      win_partition_disk_mbr "$DRIVE2" || return 1
    fi
  fi

  return 0
}

win_format_partitions() {
  local disk="$1"

  if ((UEFI == 1)); then
    local esp_part
    esp_part="$(win_get_partition "$disk" 1)"
    win_format_esp "$esp_part" || return 1

    local win_part
    win_part="$(win_get_partition "$disk" 3)"
    win_format_ntfs "$win_part" "Windows" || return 1
  else
    local sysres_part
    sysres_part="$(win_get_partition "$disk" 1)"
    win_format_ntfs "$sysres_part" "System Reserved" || return 1

    local win_part
    win_part="$(win_get_partition "$disk" 2)"
    win_format_ntfs "$win_part" "Windows" || return 1
  fi

  return 0
}

win_get_windows_partition() {
  local disk="$1"
  if ((UEFI == 1)); then
    win_get_partition "$disk" 3
  else
    win_get_partition "$disk" 2
  fi
}

win_get_boot_partition() {
  win_get_partition "$1" 1
}

apply_windows_image() {
  local wim_file="$1"
  local win_mount="$2"
  local image_index="${3:-1}"

  debug "# Windows: applying WIM image"
  win_apply_image "$wim_file" "$win_mount" "$image_index" || return 1
  return 0
}

setup_windows_bootloader() {
  local win_mount="$1"
  local boot_mount="$2"

  if ((UEFI == 1)); then
    win_setup_bootloader_uefi "$win_mount" "$boot_mount" || return 1
  else
    win_setup_bootloader_bios "$win_mount" "$boot_mount" "$DRIVE1" || return 1
  fi

  return 0
}

setup_windows_unattend() {
  local win_mount="$1"

  debug "# Windows: generating unattend.xml"

  local password
  password="$(grep "^root:" /etc/shadow 2>/dev/null | cut -d: -f2)"
  if [[ -z "$password" ]] || [[ "$password" == "!" ]] || [[ "$password" == "*" ]]; then
    password="VDSok2026!"
    debug "# Windows: using default password (no rescue password found)"
  fi

  local raw_password
  raw_password="$(cat /tmp/.rescue_password 2>/dev/null || echo 'VDSok2026!')"

  local v4_ip v4_gateway v4_netmask v4_netmask_cidr
  v4_ip="$(ip -4 addr show scope global | grep -oP 'inet \K[\d.]+'  | head -1)"
  v4_gateway="$(ip -4 route show default | grep -oP 'via \K[\d.]+' | head -1)"
  v4_netmask="$(ip -4 addr show scope global | grep -oP 'inet [\d.]+/\K\d+' | head -1)"
  v4_netmask_cidr="$v4_netmask"

  local dns1="${DNSRESOLVER[0]}"
  local dns2="${DNSRESOLVER[1]}"

  local kms_key
  kms_key="$(win_get_kms_key "$WIN_VERSION" "$WIN_EDITION")" || kms_key=""

  local hostname_short
  hostname_short="$(echo "$NEWHOSTNAME" | cut -d. -f1)"
  [[ ${#hostname_short} -gt 15 ]] && hostname_short="${hostname_short:0:15}"

  local template="$SCRIPTPATH/windows_unattend.xml.template"
  local output="$win_mount/Windows/Panther/unattend.xml"

  mkdir -p "$win_mount/Windows/Panther" 2>/dev/null

  win_generate_unattend \
    "$template" \
    "$output" \
    "$hostname_short" \
    "$raw_password" \
    "$v4_ip" \
    "" \
    "$v4_gateway" \
    "$dns1" \
    "$dns2" \
    "$kms_key" \
    "$KMS_SERVER" \
    "$WINDOWS_LOCALE" \
    "$WINDOWS_TIMEZONE" \
    "$v4_netmask_cidr" || return 1

  cp "$output" "$win_mount/Windows/System32/Sysprep/unattend.xml" 2>/dev/null

  return 0
}

setup_windows_rdp() {
  local win_mount="$1"
  debug "# Windows: enabling RDP"
  win_enable_rdp_registry "$win_mount"
  return $?
}

setup_windows_kms() {
  local win_mount="$1"
  debug "# Windows: KMS configuration is handled via unattend.xml FirstLogonCommands"
  return 0
}

setup_windows_firewall() {
  debug "# Windows: firewall rules are configured via unattend.xml FirstLogonCommands"
  return 0
}

setup_windows_drivers() {
  local win_mount="$1"

  if [[ -d "$DRIVERSPATH" ]] && [[ -n "$(ls -A "$DRIVERSPATH" 2>/dev/null)" ]]; then
    debug "# Windows: injecting drivers"
    win_inject_drivers "$win_mount" "$DRIVERSPATH" || return 1
  else
    debug "# Windows: no custom drivers to inject"
  fi

  return 0
}

setup_windows_updates() {
  local win_mount="$1"
  debug "# Windows: disabling Windows Update"
  win_disable_updates_registry "$win_mount" || true
  return 0
}

setup_windows_mirror() {
  local win_mount="$1"

  if [[ "$SWRAID" != "1" ]] || [[ -z "$DRIVE2" ]]; then
    debug "# Windows: RAID mirror not requested"
    return 0
  fi

  debug "# Windows: preparing diskpart mirror script for first boot"

  local disk2_num
  disk2_num=1

  local mirror_script
  if ((UEFI == 1)); then
    mirror_script=$(cat <<'DISKPART_UEFI'
@echo off
echo VDSok: Setting up disk mirror...
timeout /t 10

REM Convert both disks to dynamic
echo select disk 0 > %TEMP%\mirror.txt
echo convert dynamic >> %TEMP%\mirror.txt
echo select disk @@DISK2_NUM@@ >> %TEMP%\mirror.txt
echo convert dynamic >> %TEMP%\mirror.txt

REM Mirror the Windows partition
echo select volume C >> %TEMP%\mirror.txt
echo add disk=@@DISK2_NUM@@ >> %TEMP%\mirror.txt
echo exit >> %TEMP%\mirror.txt

diskpart /s %TEMP%\mirror.txt

REM Copy EFI to second disk
echo select disk @@DISK2_NUM@@ >> %TEMP%\efi_mirror.txt
echo select partition 1 >> %TEMP%\efi_mirror.txt
echo assign letter=S >> %TEMP%\efi_mirror.txt
echo exit >> %TEMP%\efi_mirror.txt
diskpart /s %TEMP%\efi_mirror.txt

xcopy /s /e /h /y M:\*.* S:\
bcdedit /copy {default} /d "Windows Server (Mirror)"

echo Disk mirror setup complete.
del "%~f0"
DISKPART_UEFI
)
  else
    mirror_script=$(cat <<'DISKPART_BIOS'
@echo off
echo VDSok: Setting up disk mirror...
timeout /t 10

REM Convert both disks to dynamic
echo select disk 0 > %TEMP%\mirror.txt
echo convert dynamic >> %TEMP%\mirror.txt
echo select disk @@DISK2_NUM@@ >> %TEMP%\mirror.txt
echo convert dynamic >> %TEMP%\mirror.txt

REM Mirror the system reserved partition
echo select volume 1 >> %TEMP%\mirror.txt
echo add disk=@@DISK2_NUM@@ >> %TEMP%\mirror.txt

REM Mirror the Windows partition
echo select volume C >> %TEMP%\mirror.txt
echo add disk=@@DISK2_NUM@@ >> %TEMP%\mirror.txt
echo exit >> %TEMP%\mirror.txt

diskpart /s %TEMP%\mirror.txt

echo Disk mirror setup complete.
del "%~f0"
DISKPART_BIOS
)
  fi

  mirror_script="${mirror_script//@@DISK2_NUM@@/$disk2_num}"

  local scripts_dir="$win_mount/Windows/Setup/Scripts"
  mkdir -p "$scripts_dir" 2>/dev/null
  echo "$mirror_script" > "$scripts_dir/setup-mirror.cmd"

  return 0
}

setup_windows_firstrun() {
  local win_mount="$1"

  debug "# Windows: setting up first-run PowerShell script"

  local postinstall_script="$SCRIPTPATH/post-install/windows-base"
  local firstrun_content

  if [[ -f "$postinstall_script" ]]; then
    firstrun_content="$(cat "$postinstall_script")"
  else
    firstrun_content=$(cat <<'PSEOF'
# VDSok post-install script
Write-Host "VDSok: Running post-install configuration..."

# Configure NTP
w32tm /config /manualpeerlist:"ntp1.vdsok.com ntp2.vdsok.com ntp3.vdsok.com" /syncfromflags:manual /reliable:yes /update
Restart-Service w32time
w32tm /resync

# Disable Server Manager auto-start (Server editions)
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    Get-ScheduledTask -TaskName ServerManager -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
}

# Disable IE Enhanced Security Configuration (Server editions)
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
if (Test-Path $AdminKey) { Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 }
if (Test-Path $UserKey) { Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 }

# Disable auto-logon after first run
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -ErrorAction SilentlyContinue

# Execute mirror setup if present
$mirrorScript = "$env:WINDIR\Setup\Scripts\setup-mirror.cmd"
if (Test-Path $mirrorScript) {
    Start-Process -FilePath $mirrorScript -Wait -NoNewWindow
}

Write-Host "VDSok: Post-install configuration complete."
PSEOF
)
  fi

  win_setup_firstrun_script "$win_mount" "$firstrun_content"

  return 0
}

run_os_specific_functions() {
  debug "# Windows: running OS-specific functions"

  local win_mount="$FOLD/hdd"

  setup_windows_rdp "$win_mount" || return 1
  setup_windows_updates "$win_mount" || return 1
  setup_windows_drivers "$win_mount" || return 1
  setup_windows_mirror "$win_mount" || return 1
  setup_windows_firstrun "$win_mount" || return 1

  return 0
}

generate_config_mdadm() { return 0; }
generate_new_ramdisk() { return 0; }
generate_config_grub() { return 0; }
write_grub() { return 0; }

# vim: ai:ts=2:sw=2:et
