#!/usr/bin/env bash

#
# windows installation helper functions
#
# (c) 2026, VDSok
#

declare -A WIN_KMS_KEYS=(
  # Windows Server 2025
  ["server2025datacenter"]="D764K-2NDRG-47T6Q-P8T8W-YP6DF"
  ["server2025standard"]="TVRH6-WHNXV-R9WG3-9XRFY-MY832"
  # Windows Server 2022
  ["server2022datacenter"]="WX4NM-KYWYW-QJJR4-XV3QB-6VM33"
  ["server2022standard"]="VDYBN-27WPP-V4HQT-9VMD4-VMK7H"
  # Windows Server 2019
  ["server2019datacenter"]="WMDGN-G9PQG-XVVXX-R3X43-63DFG"
  ["server2019standard"]="N69G4-B89J2-4G8F4-WWYCC-J464C"
  # Windows 11
  ["win11pro"]="W269N-WFGWX-YVC9B-4J6C9-T83GX"
  ["win11enterprise"]="NPPR9-FWDCX-D2C8J-H872K-2YT43"
  # Windows 10
  ["win10pro"]="W269N-WFGWX-YVC9B-4J6C9-T83GX"
  ["win10enterprise"]="NPPR9-FWDCX-D2C8J-H872K-2YT43"
)

win_check_requirements() {
  local missing=()

  if ! command -v wimapply &>/dev/null && ! command -v wimlib-imagex &>/dev/null; then
    missing+=("wimtools (wimlib-imagex)")
  fi

  if ! command -v ntfs-3g &>/dev/null; then
    missing+=("ntfs-3g")
  fi

  if ! command -v chntpw &>/dev/null; then
    missing+=("chntpw")
  fi

  if ! command -v parted &>/dev/null && ! command -v sfdisk &>/dev/null; then
    missing+=("parted or sfdisk")
  fi

  if ((${#missing[@]} > 0)); then
    debug "# Missing requirements: ${missing[*]}"
    echo "ERROR: Missing required tools for Windows installation: ${missing[*]}"
    echo "Install them with: apt-get install -y wimtools ntfs-3g chntpw parted"
    return 1
  fi

  return 0
}

win_install_requirements() {
  debug "# Installing Windows installation requirements"
  apt-get update -qq 2>&1 | debugoutput
  apt-get install -y -qq wimtools ntfs-3g chntpw parted 2>&1 | debugoutput
  return $?
}

win_get_wimapply_cmd() {
  if command -v wimapply &>/dev/null; then
    echo "wimapply"
  elif command -v wimlib-imagex &>/dev/null; then
    echo "wimlib-imagex apply"
  else
    return 1
  fi
}

win_get_wiminfo_cmd() {
  if command -v wiminfo &>/dev/null; then
    echo "wiminfo"
  elif command -v wimlib-imagex &>/dev/null; then
    echo "wimlib-imagex info"
  else
    return 1
  fi
}

win_partition_disk_gpt() {
  local disk="$1"
  debug "# Creating GPT partition table on $disk for Windows (UEFI)"

  parted -s "$disk" mklabel gpt 2>&1 | debugoutput || return 1

  # EFI System Partition (100MB)
  parted -s "$disk" mkpart primary fat32 1MiB 101MiB 2>&1 | debugoutput || return 1
  parted -s "$disk" set 1 esp on 2>&1 | debugoutput || return 1

  # Microsoft Reserved Partition (16MB)
  parted -s "$disk" mkpart primary ntfs 101MiB 117MiB 2>&1 | debugoutput || return 1
  parted -s "$disk" set 2 msftres on 2>&1 | debugoutput || return 1

  # Windows C: partition (remaining space)
  parted -s "$disk" mkpart primary ntfs 117MiB 100% 2>&1 | debugoutput || return 1

  partprobe "$disk" 2>&1 | debugoutput
  sleep 2

  return 0
}

win_partition_disk_mbr() {
  local disk="$1"
  debug "# Creating MBR partition table on $disk for Windows (Legacy BIOS)"

  parted -s "$disk" mklabel msdos 2>&1 | debugoutput || return 1

  # System Reserved partition (350MB, active, NTFS)
  parted -s "$disk" mkpart primary ntfs 1MiB 351MiB 2>&1 | debugoutput || return 1
  parted -s "$disk" set 1 boot on 2>&1 | debugoutput || return 1

  # Windows C: partition (remaining space)
  parted -s "$disk" mkpart primary ntfs 351MiB 100% 2>&1 | debugoutput || return 1

  partprobe "$disk" 2>&1 | debugoutput
  sleep 2

  return 0
}

win_get_partition() {
  local disk="$1"
  local partnum="$2"

  if [[ "$disk" == *nvme* ]] || [[ "$disk" == *mmcblk* ]]; then
    echo "${disk}p${partnum}"
  else
    echo "${disk}${partnum}"
  fi
}

win_format_esp() {
  local part="$1"
  debug "# Formatting ESP partition $part"
  mkfs.fat -F32 -n "SYSTEM" "$part" 2>&1 | debugoutput
  return $?
}

win_format_ntfs() {
  local part="$1"
  local label="${2:-Windows}"
  debug "# Formatting NTFS partition $part with label $label"
  mkfs.ntfs -f -L "$label" "$part" 2>&1 | debugoutput
  return $?
}

win_mount_ntfs() {
  local part="$1"
  local mountpoint="$2"
  debug "# Mounting NTFS $part at $mountpoint"
  mkdir -p "$mountpoint" 2>/dev/null
  mount -t ntfs-3g "$part" "$mountpoint" 2>&1 | debugoutput
  return $?
}

win_umount() {
  local mountpoint="$1"
  debug "# Unmounting $mountpoint"
  sync
  umount -l "$mountpoint" 2>&1 | debugoutput
  return $?
}

win_apply_image() {
  local wim_file="$1"
  local target="$2"
  local image_index="${3:-1}"

  debug "# Applying WIM image $wim_file (index $image_index) to $target"

  local apply_cmd
  apply_cmd="$(win_get_wimapply_cmd)" || return 1

  $apply_cmd "$wim_file" "$image_index" "$target" 2>&1 | debugoutput
  return $?
}

win_setup_bootloader_uefi() {
  local win_mount="$1"
  local esp_mount="$2"

  debug "# Setting up Windows UEFI bootloader"

  mkdir -p "$esp_mount/EFI/Microsoft/Boot" 2>/dev/null
  mkdir -p "$esp_mount/EFI/Boot" 2>/dev/null

  if [[ -f "$win_mount/Windows/Boot/EFI/bootmgfw.efi" ]]; then
    cp "$win_mount/Windows/Boot/EFI/bootmgfw.efi" "$esp_mount/EFI/Microsoft/Boot/" 2>&1 | debugoutput
    cp "$win_mount/Windows/Boot/EFI/bootmgfw.efi" "$esp_mount/EFI/Boot/bootx64.efi" 2>&1 | debugoutput
  else
    debug "# WARNING: bootmgfw.efi not found, bootloader may not work"
    return 1
  fi

  if [[ -d "$win_mount/Windows/Boot/EFI" ]]; then
    cp -r "$win_mount/Windows/Boot/EFI/"* "$esp_mount/EFI/Microsoft/Boot/" 2>&1 | debugoutput
  fi

  local bcd_template="$win_mount/Windows/Boot/EFI/BCD"
  if [[ -f "$bcd_template" ]]; then
    cp "$bcd_template" "$esp_mount/EFI/Microsoft/Boot/BCD" 2>&1 | debugoutput
  fi

  return 0
}

win_setup_bootloader_bios() {
  local win_mount="$1"
  local sysreserved_mount="$2"
  local disk="$3"

  debug "# Setting up Windows Legacy BIOS bootloader"

  if [[ -d "$win_mount/Windows/Boot/PCAT" ]]; then
    mkdir -p "$sysreserved_mount/Boot" 2>/dev/null
    cp -r "$win_mount/Windows/Boot/PCAT/"* "$sysreserved_mount/Boot/" 2>&1 | debugoutput
  fi

  local bcd_template="$win_mount/Windows/Boot/PCAT/BCD"
  if [[ -f "$bcd_template" ]]; then
    cp "$bcd_template" "$sysreserved_mount/Boot/BCD" 2>&1 | debugoutput
  fi

  if [[ -f "$win_mount/Windows/Boot/PCAT/bootmgr" ]]; then
    cp "$win_mount/Windows/Boot/PCAT/bootmgr" "$sysreserved_mount/" 2>&1 | debugoutput
  fi

  if command -v ms-sys &>/dev/null; then
    ms-sys -7 "$disk" 2>&1 | debugoutput
    local sysreserved_part
    sysreserved_part="$(win_get_partition "$disk" 1)"
    ms-sys -n "$sysreserved_part" 2>&1 | debugoutput
  fi

  return 0
}

win_generate_unattend() {
  local template="$1"
  local output="$2"
  local hostname="$3"
  local password="$4"
  local ip_addr="$5"
  local netmask="$6"
  local gateway="$7"
  local dns1="$8"
  local dns2="$9"
  local kms_key="${10}"
  local kms_server="${11}"
  local locale="${12}"
  local timezone="${13}"
  local netmask_cidr="${14}"

  debug "# Generating unattend.xml from template"

  local content
  content="$(< "$template")"

  content="${content//@@HOSTNAME@@/$hostname}"
  content="${content//@@PASSWORD@@/$password}"
  content="${content//@@IP_ADDRESS@@/$ip_addr}"
  content="${content//@@NETMASK@@/$netmask}"
  content="${content//@@NETMASK_CIDR@@/$netmask_cidr}"
  content="${content//@@GATEWAY@@/$gateway}"
  content="${content//@@DNS1@@/$dns1}"
  content="${content//@@DNS2@@/$dns2}"
  content="${content//@@KMS_KEY@@/$kms_key}"
  content="${content//@@KMS_SERVER@@/$kms_server}"
  content="${content//@@LOCALE@@/$locale}"
  content="${content//@@TIMEZONE@@/$timezone}"

  echo "$content" > "$output"
  return $?
}

win_offline_reg_load() {
  local hive_file="$1"
  local key_name="$2"
  debug "# Loading registry hive $hive_file as $key_name"
  return 0
}

win_set_admin_password() {
  local win_mount="$1"
  local password="$2"
  local sam_file="$win_mount/Windows/System32/config/SAM"

  debug "# Setting Administrator password via chntpw"

  if [[ ! -f "$sam_file" ]]; then
    debug "# SAM file not found at $sam_file"
    return 1
  fi

  echo -e "$password\n$password\ny\nq\n" | chntpw -u Administrator "$sam_file" 2>&1 | debugoutput || true
  return 0
}

win_enable_rdp_registry() {
  local win_mount="$1"
  local system_hive="$win_mount/Windows/System32/config/SYSTEM"

  debug "# Enabling RDP via offline registry edit"

  if [[ ! -f "$system_hive" ]]; then
    debug "# SYSTEM hive not found"
    return 1
  fi

  chntpw -e "$system_hive" <<'REGEOF' 2>&1 | debugoutput || true
cd ControlSet001\Control\Terminal Server
ed fDenyTSConnections
0
q
y
REGEOF
  return 0
}

win_disable_updates_registry() {
  local win_mount="$1"
  local software_hive="$win_mount/Windows/System32/config/SOFTWARE"

  debug "# Disabling Windows Update via offline registry"

  if [[ ! -f "$software_hive" ]]; then
    debug "# SOFTWARE hive not found"
    return 1
  fi

  chntpw -e "$software_hive" <<'REGEOF' 2>&1 | debugoutput || true
cd Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update
nv 4 AUOptions
ed AUOptions
1
q
y
REGEOF
  return 0
}

win_inject_drivers() {
  local win_mount="$1"
  local drivers_path="$2"

  debug "# Injecting drivers from $drivers_path"

  if [[ ! -d "$drivers_path" ]] || [[ -z "$(ls -A "$drivers_path" 2>/dev/null)" ]]; then
    debug "# No drivers to inject (path empty or not found)"
    return 0
  fi

  local wimupdate_cmd
  if command -v wimlib-imagex &>/dev/null; then
    wimupdate_cmd="wimlib-imagex update"
  else
    debug "# wimlib-imagex not found for driver injection, copying directly"
    mkdir -p "$win_mount/Windows/INF/VDSok" 2>/dev/null
    find "$drivers_path" -type f \( -name "*.inf" -o -name "*.sys" -o -name "*.cat" \) \
      -exec cp {} "$win_mount/Windows/INF/VDSok/" \; 2>&1 | debugoutput
    return $?
  fi

  mkdir -p "$win_mount/Drivers" 2>/dev/null
  cp -r "$drivers_path"/* "$win_mount/Drivers/" 2>&1 | debugoutput

  return 0
}

win_setup_firstrun_script() {
  local win_mount="$1"
  local script_content="$2"

  debug "# Setting up FirstRun PowerShell script"

  local scripts_dir="$win_mount/Windows/Setup/Scripts"
  mkdir -p "$scripts_dir" 2>/dev/null

  echo "$script_content" > "$scripts_dir/vdsok-firstrun.ps1"

  cat > "$scripts_dir/SetupComplete.cmd" << 'CMDEOF'
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\vdsok-firstrun.ps1"
CMDEOF

  return 0
}

win_get_kms_key() {
  local version="$1"
  local edition="$2"
  local key_name

  case "${version,,}" in
    2025|server2025) key_name="server2025${edition,,}" ;;
    2022|server2022) key_name="server2022${edition,,}" ;;
    2019|server2019) key_name="server2019${edition,,}" ;;
    10|win10)        key_name="win10${edition,,}" ;;
    11|win11)        key_name="win11${edition,,}" ;;
    *) return 1 ;;
  esac

  local key="${WIN_KMS_KEYS[$key_name]}"
  if [[ -n "$key" ]]; then
    echo "$key"
    return 0
  fi
  return 1
}

win_image_info() {
  local wim_file="$1"
  local info_cmd
  info_cmd="$(win_get_wiminfo_cmd)" || return 1
  $info_cmd "$wim_file" 2>&1
}

win_netmask_to_cidr() {
  local netmask="$1"
  local cidr=0
  local IFS='.'
  for octet in $netmask; do
    case $octet in
      255) ((cidr+=8)) ;;
      254) ((cidr+=7)) ;;
      252) ((cidr+=6)) ;;
      248) ((cidr+=5)) ;;
      240) ((cidr+=4)) ;;
      224) ((cidr+=3)) ;;
      192) ((cidr+=2)) ;;
      128) ((cidr+=1)) ;;
      0) ;;
    esac
  done
  echo "$cidr"
}

win_is_windows_image() {
  local filename="$1"
  case "${filename,,}" in
    *.wim) return 0 ;;
    *windows*|*win-server*|*winserver*|*win10*|*win11*)
      return 0
      ;;
  esac
  return 1
}

# vim: ai:ts=2:sw=2:et
