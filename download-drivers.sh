#!/usr/bin/env bash
#
# VDSok Install — Driver Downloader
# Downloads Windows drivers for offline injection
# Run from Linux rescue environment before installation
#
# Usage: bash download-drivers.sh [--all|--network|--display|--chipset|--storage]
#

set -euo pipefail

SCRIPTPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVERSPATH="$SCRIPTPATH/drivers"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

need_cmd() {
    if ! command -v "$1" &>/dev/null; then
        error "'$1' not found. Install it: apt-get install -y $2"
        return 1
    fi
}

check_deps() {
    need_cmd curl   curl
    need_cmd unzip  unzip
    need_cmd cabextract cabextract || true
}

download_file() {
    local url="$1" dest="$2" desc="$3"
    info "Downloading $desc..."
    if curl -fsSL -o "$dest" "$url" 2>/dev/null; then
        local sz
        sz=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
        if (( sz > 1000 )); then
            info "  OK: $(( sz / 1024 )) KB -> $dest"
            return 0
        fi
    fi
    warn "  Failed to download $desc from $url"
    return 1
}

# ─────────────────────────────────────────────
# Intel Ethernet (I210, I350, E810, X710, etc.)
# ─────────────────────────────────────────────
download_intel_network() {
    local dest_dir="$DRIVERSPATH/network/intel"
    if [[ -d "$dest_dir" ]] && (( $(find "$dest_dir" -name "*.inf" 2>/dev/null | wc -l) > 0 )); then
        info "Intel network drivers already present, skipping"
        return 0
    fi

    mkdir -p "$dest_dir"
    local tmpzip="/tmp/intel-net.zip"

    local urls=(
        "https://downloadmirror.intel.com/838943/Wired_driver_31.1_x64.zip"
        "https://downloadmirror.intel.com/727998/Wired_driver_31.1_x64.zip"
        "https://downloadmirror.intel.com/706171/Wired_driver_31.1_x64.zip"
    )

    local ok=false
    for url in "${urls[@]}"; do
        if download_file "$url" "$tmpzip" "Intel Ethernet v31.1"; then
            ok=true
            break
        fi
    done

    if $ok; then
        info "  Extracting Intel drivers..."
        unzip -qo "$tmpzip" -d "/tmp/intel-net-extract"
        cp -r /tmp/intel-net-extract/PRO* "$dest_dir/" 2>/dev/null || true
        local count
        count=$(find "$dest_dir" -name "*.inf" | wc -l)
        info "  Intel network: $count INF files installed"
        rm -rf /tmp/intel-net-extract "$tmpzip"
    else
        error "Could not download Intel drivers."
        echo "  Please download manually from:"
        echo "  https://www.intel.com/content/www/us/en/download/838943/"
        echo "  Extract to: $dest_dir/"
    fi
}

# ─────────────────────────────────────────────
# Realtek Ethernet (RTL8168, RTL8125, RTL8111)
# ─────────────────────────────────────────────
download_realtek_network() {
    local dest_dir="$DRIVERSPATH/network/realtek"
    if [[ -d "$dest_dir" ]] && (( $(find "$dest_dir" -name "*.inf" 2>/dev/null | wc -l) > 0 )); then
        info "Realtek network drivers already present, skipping"
        return 0
    fi

    mkdir -p "$dest_dir"
    local tmpzip="/tmp/realtek-net.zip"

    local urls=(
        "https://rtitwww.realtek.com/rtdrivers/cn/nic1/Install_PCIE_Win11_11025_05272025.zip"
        "https://rtitwww.realtek.com/rtdrivers/cn/nic1/Install_Win11_11025_05272025.zip"
    )

    local ok=false
    for url in "${urls[@]}"; do
        if download_file "$url" "$tmpzip" "Realtek Ethernet"; then
            ok=true
            break
        fi
    done

    if $ok; then
        info "  Extracting Realtek drivers..."
        unzip -qo "$tmpzip" -d "/tmp/realtek-extract"
        find /tmp/realtek-extract -type f \( -name "*.inf" -o -name "*.sys" -o -name "*.cat" \) \
            -exec cp {} "$dest_dir/" \;
        local count
        count=$(find "$dest_dir" -name "*.inf" | wc -l)
        info "  Realtek network: $count INF files installed"
        rm -rf /tmp/realtek-extract "$tmpzip"
    else
        warn "Could not download Realtek drivers from official mirror."
        echo "  Download manually from: https://www.realtek.com/Download/List?cate_id=584"
        echo "  Extract to: $dest_dir/"
    fi
}

# ─────────────────────────────────────────────
# ASPEED Display (AST2400/2500/2600 BMC VGA)
# ─────────────────────────────────────────────
download_aspeed_display() {
    local dest_dir="$DRIVERSPATH/display/aspeed"
    if [[ -d "$dest_dir" ]] && (( $(find "$dest_dir" -name "*.inf" 2>/dev/null | wc -l) > 0 )); then
        info "ASPEED display drivers already present, skipping"
        return 0
    fi

    mkdir -p "$dest_dir"
    local tmpzip="/tmp/aspeed-display.zip"

    local urls=(
        "https://www.aspeedtech.com/dl_drivers/v11601_windows.zip"
        "https://ftp.aspeedtech.com/BIOS/v11601_windows.zip"
    )

    local ok=false
    for url in "${urls[@]}"; do
        if download_file "$url" "$tmpzip" "ASPEED Display v1.16.01"; then
            ok=true
            break
        fi
    done

    if $ok; then
        info "  Extracting ASPEED drivers..."
        unzip -qo "$tmpzip" -d "/tmp/aspeed-extract"
        find /tmp/aspeed-extract -type f \( -name "*.inf" -o -name "*.sys" -o -name "*.cat" \) \
            -exec cp {} "$dest_dir/" \;
        local count
        count=$(find "$dest_dir" -name "*.inf" | wc -l)
        info "  ASPEED display: $count INF files installed"
        rm -rf /tmp/aspeed-extract "$tmpzip"
    else
        warn "Could not download ASPEED drivers."
        echo "  Note: Windows Server uses Microsoft Basic Display Adapter by default."
        echo "  For ASPEED support, download from: https://www.aspeedtech.com/support_driver/"
        echo "  Extract to: $dest_dir/"
    fi
}

# ─────────────────────────────────────────────
# Intel Chipset INF
# ─────────────────────────────────────────────
download_intel_chipset() {
    local dest_dir="$DRIVERSPATH/chipset/intel"
    if [[ -d "$dest_dir" ]] && (( $(find "$dest_dir" -name "*.inf" 2>/dev/null | wc -l) > 0 )); then
        info "Intel chipset INF already present, skipping"
        return 0
    fi

    mkdir -p "$dest_dir"

    info "Intel Chipset INF is bundled with Windows Server inbox drivers."
    info "Additional chipset INFs can be obtained from:"
    echo "  https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html"
    echo "  Extract SetupChipset.exe to: $dest_dir/"
    info "Skipping chipset download (inbox drivers sufficient for most servers)."
}

# ─────────────────────────────────────────────
# Broadcom / LSI MegaRAID Storage
# ─────────────────────────────────────────────
download_broadcom_storage() {
    local dest_dir="$DRIVERSPATH/storage/broadcom"
    if [[ -d "$dest_dir" ]] && (( $(find "$dest_dir" -name "*.inf" 2>/dev/null | wc -l) > 0 )); then
        info "Broadcom storage drivers already present, skipping"
        return 0
    fi

    mkdir -p "$dest_dir"

    info "Broadcom MegaRAID drivers are included in Windows Server inbox."
    info "For latest drivers, download from:"
    echo "  https://www.broadcom.com/support/download-search"
    echo "  Search for your controller model (9560, 9540, 9460, etc.)"
    echo "  Extract to: $dest_dir/"
    info "Skipping storage download (inbox drivers sufficient for most controllers)."
}

# ─────────────────────────────────────────────
# VirtIO (QEMU/KVM virtual machines)
# ─────────────────────────────────────────────
download_virtio() {
    local dest_dir="$DRIVERSPATH/network/virtio"
    if [[ -d "$dest_dir" ]] && (( $(find "$dest_dir" -name "*.inf" 2>/dev/null | wc -l) > 0 )); then
        info "VirtIO drivers already present, skipping"
        return 0
    fi

    mkdir -p "$dest_dir"
    local tmpiso="/tmp/virtio-win.iso"

    info "Downloading VirtIO drivers for QEMU/KVM..."
    if download_file "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" \
        "$tmpiso" "VirtIO stable ISO"; then

        info "  Mounting and extracting VirtIO drivers..."
        local mnt="/tmp/virtio-mnt"
        mkdir -p "$mnt"
        mount -o loop,ro "$tmpiso" "$mnt" 2>/dev/null || {
            warn "Cannot mount ISO. Install mount/loop support."
            rm -f "$tmpiso"
            return 1
        }

        for subdir in NetKVM viostor vioscsi; do
            if [[ -d "$mnt/$subdir" ]]; then
                local target="$DRIVERSPATH/network/virtio/$subdir"
                [[ "$subdir" != "NetKVM" ]] && target="$DRIVERSPATH/storage/virtio/$subdir"
                mkdir -p "$target"
                find "$mnt/$subdir" -path "*/amd64/*" -type f \( -name "*.inf" -o -name "*.sys" -o -name "*.cat" \) \
                    -exec cp {} "$target/" \;
            fi
        done

        umount "$mnt" 2>/dev/null
        rm -rf "$mnt" "$tmpiso"

        local count
        count=$(find "$DRIVERSPATH/network/virtio" "$DRIVERSPATH/storage/virtio" -name "*.inf" 2>/dev/null | wc -l)
        info "  VirtIO: $count INF files installed"
    else
        warn "Could not download VirtIO ISO."
        echo "  Download manually from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/"
    fi
}

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
show_summary() {
    echo ""
    info "=== Driver Summary ==="
    for cat_dir in network storage display chipset; do
        local dir="$DRIVERSPATH/$cat_dir"
        if [[ -d "$dir" ]]; then
            local inf_count
            inf_count=$(find "$dir" -name "*.inf" 2>/dev/null | wc -l)
            local total_size
            total_size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            printf "  %-10s %3d INF files  (%s)\n" "$cat_dir:" "$inf_count" "$total_size"
        fi
    done
    echo ""
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
    local target="${1:---all}"

    info "VDSok Install — Driver Downloader"
    info "Drivers directory: $DRIVERSPATH"
    echo ""

    check_deps

    case "$target" in
        --all)
            download_intel_network
            download_realtek_network
            download_aspeed_display
            download_intel_chipset
            download_broadcom_storage
            download_virtio
            ;;
        --network)
            download_intel_network
            download_realtek_network
            download_virtio
            ;;
        --display)
            download_aspeed_display
            ;;
        --chipset)
            download_intel_chipset
            ;;
        --storage)
            download_broadcom_storage
            ;;
        --virtio)
            download_virtio
            ;;
        *)
            echo "Usage: $0 [--all|--network|--display|--chipset|--storage|--virtio]"
            exit 1
            ;;
    esac

    show_summary
    info "Done!"
}

main "$@"
