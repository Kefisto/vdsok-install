#!/usr/bin/env bash
#
# VDSok Install — Windows Image Downloader
# Downloads Windows Server evaluation ISOs from Microsoft
# and extracts WIM images for use with vdsok-install
#
# Usage:
#   bash download-images.sh                     # interactive menu
#   bash download-images.sh --server2022        # download Server 2022
#   bash download-images.sh --server2025        # download Server 2025
#   bash download-images.sh --all               # download all
#   bash download-images.sh --from-iso /path/to/file.iso   # extract WIM from local ISO
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/../images"
TEMP_DIR="/tmp/vdsok-images"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─────────────────────────────────────
# Dependencies
# ─────────────────────────────────────
install_deps() {
    local need_install=()

    for cmd in curl wimlib-imagex 7z; do
        if ! command -v "$cmd" &>/dev/null; then
            case "$cmd" in
                wimlib-imagex) need_install+=(wimtools) ;;
                7z)           need_install+=(p7zip-full) ;;
                curl)         need_install+=(curl) ;;
            esac
        fi
    done

    if ((${#need_install[@]} > 0)); then
        info "Installing dependencies: ${need_install[*]}"
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq "${need_install[@]}"
        elif command -v yum &>/dev/null; then
            for pkg in "${need_install[@]}"; do
                [[ "$pkg" == "wimtools" ]] && pkg="wimlib-utils"
                [[ "$pkg" == "p7zip-full" ]] && pkg="p7zip p7zip-plugins"
                yum install -y $pkg
            done
        fi
    fi
}

# ─────────────────────────────────────
# Extract WIM from ISO
# ─────────────────────────────────────
extract_wim_from_iso() {
    local iso_path="$1"
    local output_prefix="$2"
    local mount_dir="${TEMP_DIR}/iso_mount"

    info "Extracting install.wim from $(basename "$iso_path")..."

    mkdir -p "$mount_dir" "$IMAGES_DIR"

    # Try mounting first, fall back to 7z
    local wim_source=""
    if mount -o loop,ro "$iso_path" "$mount_dir" 2>/dev/null; then
        if [[ -f "$mount_dir/sources/install.wim" ]]; then
            wim_source="$mount_dir/sources/install.wim"
        elif [[ -f "$mount_dir/sources/install.esd" ]]; then
            wim_source="$mount_dir/sources/install.esd"
        fi

        if [[ -n "$wim_source" ]]; then
            info "Found: $wim_source"
            cp "$wim_source" "${TEMP_DIR}/install.wim"
        fi
        umount "$mount_dir" 2>/dev/null || true
    else
        info "Mount failed, using 7z..."
        if command -v 7z &>/dev/null; then
            7z e -o"${TEMP_DIR}" "$iso_path" "sources/install.wim" "sources/install.esd" -y 2>/dev/null || true
            if [[ -f "${TEMP_DIR}/install.wim" ]]; then
                wim_source="${TEMP_DIR}/install.wim"
            elif [[ -f "${TEMP_DIR}/install.esd" ]]; then
                mv "${TEMP_DIR}/install.esd" "${TEMP_DIR}/install.wim"
                wim_source="${TEMP_DIR}/install.wim"
            fi
        else
            error "Cannot extract ISO: mount and 7z both failed"
            return 1
        fi
    fi

    if [[ ! -f "${TEMP_DIR}/install.wim" ]]; then
        error "install.wim not found in ISO"
        return 1
    fi

    info "WIM contents:"
    wimlib-imagex info "${TEMP_DIR}/install.wim" | grep -E "^(Image Count|Image [0-9]|Name|Description)" || true
    echo ""

    local image_count
    image_count=$(wimlib-imagex info "${TEMP_DIR}/install.wim" | grep "Image Count" | awk '{print $NF}')

    for ((i=1; i<=image_count; i++)); do
        local name
        name=$(wimlib-imagex info "${TEMP_DIR}/install.wim" "$i" | grep "^Name:" | sed 's/^Name:[[:space:]]*//')

        local wim_filename
        wim_filename=$(name_to_filename "$name" "$output_prefix")

        if [[ -n "$wim_filename" ]]; then
            local dest="${IMAGES_DIR}/${wim_filename}"
            if [[ -f "$dest" ]]; then
                warn "Already exists: $dest — skipping"
                continue
            fi
            info "Exporting image $i ($name) -> $wim_filename"
            wimlib-imagex export "${TEMP_DIR}/install.wim" "$i" "$dest" 2>/dev/null
            info "  Saved: $dest ($(du -h "$dest" | cut -f1))"
        fi
    done

    rm -f "${TEMP_DIR}/install.wim"
    info "Done extracting from $(basename "$iso_path")"
}

# ─────────────────────────────────────
# Map edition name to WIM filename
# ─────────────────────────────────────
name_to_filename() {
    local name="$1"
    local prefix="$2"

    case "$name" in
        *"Datacenter"*"Desktop"*|*"Datacenter (Desktop Experience)"*)
            echo "${prefix}-Datacenter-amd64.wim" ;;
        *"Datacenter"*)
            echo "${prefix}-Datacenter-core-amd64.wim" ;;
        *"Standard"*"Desktop"*|*"Standard (Desktop Experience)"*)
            echo "${prefix}-Standard-amd64.wim" ;;
        *"Standard"*)
            echo "${prefix}-Standard-core-amd64.wim" ;;
        *"Pro"*)
            echo "${prefix}-Pro-amd64.wim" ;;
        *"Enterprise"*)
            echo "${prefix}-Enterprise-amd64.wim" ;;
        *"Home"*)
            echo "${prefix}-Home-amd64.wim" ;;
        *)
            local safe_name
            safe_name=$(echo "$name" | tr ' ' '-' | tr -cd 'A-Za-z0-9-')
            echo "${prefix}-${safe_name}-amd64.wim" ;;
    esac
}

# ─────────────────────────────────────
# Download ISO from URL with resume support
# ─────────────────────────────────────
download_iso() {
    local url="$1"
    local dest="$2"

    if [[ -f "$dest" ]]; then
        local existing_size
        existing_size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        if ((existing_size > 1000000000)); then
            info "ISO already downloaded: $dest ($(du -h "$dest" | cut -f1))"
            return 0
        fi
    fi

    info "Downloading $(basename "$dest")..."
    info "URL: $url"
    echo ""

    curl -L -o "$dest" -C - \
        --retry 3 --retry-delay 5 \
        --progress-bar \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        "$url"

    if [[ -f "$dest" ]]; then
        local size
        size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        if ((size < 1000000)); then
            error "Downloaded file too small ($(du -h "$dest" | cut -f1)), likely not a valid ISO"
            head -c 500 "$dest" 2>/dev/null
            echo ""
            rm -f "$dest"
            return 1
        fi
        info "Downloaded: $(du -h "$dest" | cut -f1)"
    else
        error "Download failed"
        return 1
    fi
}

# ─────────────────────────────────────
# Microsoft Evaluation Center API
# ─────────────────────────────────────
get_eval_download_url() {
    local product="$1"
    local lang="${2:-en-us}"

    local culture="en-us"
    local country="US"

    case "$lang" in
        ru*) culture="ru-ru"; country="RU" ;;
        en*) culture="en-us"; country="US" ;;
        de*) culture="de-de"; country="DE" ;;
    esac

    local page_url=""
    case "$product" in
        server2022) page_url="https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022" ;;
        server2025) page_url="https://www.microsoft.com/en-us/evalcenter/download-windows-server-2025" ;;
        server2019) page_url="https://www.microsoft.com/en-us/evalcenter/download-windows-server-2019" ;;
    esac

    echo "$page_url"
}

# ─────────────────────────────────────
# Download Windows Server 2022
# ─────────────────────────────────────
download_server_2022() {
    local iso_file="${TEMP_DIR}/windows-server-2022.iso"
    local eval_url

    echo -e "\n${CYAN}═══ Windows Server 2022 ═══${NC}\n"

    eval_url=$(get_eval_download_url "server2022")

    echo -e "${YELLOW}Microsoft Evaluation Center не поддерживает прямое скачивание через curl.${NC}"
    echo -e "${YELLOW}Скачайте ISO одним из способов:${NC}\n"
    echo -e "  1. ${GREEN}Microsoft Evaluation Center${NC} (180 дней, бесплатно):"
    echo -e "     $eval_url\n"
    echo -e "  2. ${GREEN}Massgrave.dev${NC} (полная версия, оригинальные файлы Microsoft):"
    echo -e "     https://massgrave.dev/windows-server-links\n"
    echo -e "  3. ${GREEN}Если ISO уже скачан${NC}, укажите путь:\n"

    if [[ -f "$iso_file" ]]; then
        info "Найден ранее скачанный ISO: $iso_file"
        extract_wim_from_iso "$iso_file" "Windows-Server2022"
        return 0
    fi

    local found_iso=""
    for f in /root/*.iso /tmp/*.iso /home/*/*.iso; do
        if [[ -f "$f" ]] && [[ "$f" == *[Ss]erver*2022* || "$f" == *SERVER*2022* ]]; then
            found_iso="$f"
            break
        fi
    done

    if [[ -n "$found_iso" ]]; then
        info "Найден ISO: $found_iso"
        extract_wim_from_iso "$found_iso" "Windows-Server2022"
        return 0
    fi

    read -r -p "Введите путь к ISO файлу (или URL, или Enter для пропуска): " user_input
    if [[ -z "$user_input" ]]; then
        warn "Пропущено"
        return 0
    fi

    if [[ "$user_input" == http* ]]; then
        download_iso "$user_input" "$iso_file" || return 1
        extract_wim_from_iso "$iso_file" "Windows-Server2022"
    elif [[ -f "$user_input" ]]; then
        extract_wim_from_iso "$user_input" "Windows-Server2022"
    else
        error "Файл не найден: $user_input"
        return 1
    fi
}

# ─────────────────────────────────────
# Download Windows Server 2025
# ─────────────────────────────────────
download_server_2025() {
    local iso_file="${TEMP_DIR}/windows-server-2025.iso"

    echo -e "\n${CYAN}═══ Windows Server 2025 ═══${NC}\n"

    echo -e "${YELLOW}Скачайте ISO одним из способов:${NC}\n"
    echo -e "  1. ${GREEN}Microsoft Evaluation Center${NC} (180 дней, бесплатно):"
    echo -e "     https://www.microsoft.com/en-us/evalcenter/download-windows-server-2025\n"
    echo -e "  2. ${GREEN}Massgrave.dev${NC} (полная версия, оригинальные файлы Microsoft):"
    echo -e "     https://massgrave.dev/windows-server-links\n"

    if [[ -f "$iso_file" ]]; then
        info "Найден ранее скачанный ISO: $iso_file"
        extract_wim_from_iso "$iso_file" "Windows-Server2025"
        return 0
    fi

    local found_iso=""
    for f in /root/*.iso /tmp/*.iso /home/*/*.iso; do
        if [[ -f "$f" ]] && [[ "$f" == *[Ss]erver*2025* || "$f" == *SERVER*2025* ]]; then
            found_iso="$f"
            break
        fi
    done

    if [[ -n "$found_iso" ]]; then
        info "Найден ISO: $found_iso"
        extract_wim_from_iso "$found_iso" "Windows-Server2025"
        return 0
    fi

    read -r -p "Введите путь к ISO файлу (или URL, или Enter для пропуска): " user_input
    if [[ -z "$user_input" ]]; then
        warn "Пропущено"
        return 0
    fi

    if [[ "$user_input" == http* ]]; then
        download_iso "$user_input" "$iso_file" || return 1
        extract_wim_from_iso "$iso_file" "Windows-Server2025"
    elif [[ -f "$user_input" ]]; then
        extract_wim_from_iso "$user_input" "Windows-Server2025"
    else
        error "Файл не найден: $user_input"
        return 1
    fi
}

# ─────────────────────────────────────
# Download Windows Server 2019
# ─────────────────────────────────────
download_server_2019() {
    local iso_file="${TEMP_DIR}/windows-server-2019.iso"

    echo -e "\n${CYAN}═══ Windows Server 2019 ═══${NC}\n"

    echo -e "${YELLOW}Скачайте ISO одним из способов:${NC}\n"
    echo -e "  1. ${GREEN}Microsoft Evaluation Center${NC} (180 дней, бесплатно):"
    echo -e "     https://www.microsoft.com/en-us/evalcenter/download-windows-server-2019\n"
    echo -e "  2. ${GREEN}Massgrave.dev${NC}:"
    echo -e "     https://massgrave.dev/windows-server-links\n"

    if [[ -f "$iso_file" ]]; then
        info "Найден ранее скачанный ISO: $iso_file"
        extract_wim_from_iso "$iso_file" "Windows-Server2019"
        return 0
    fi

    local found_iso=""
    for f in /root/*.iso /tmp/*.iso /home/*/*.iso; do
        if [[ -f "$f" ]] && [[ "$f" == *[Ss]erver*2019* || "$f" == *SERVER*2019* ]]; then
            found_iso="$f"
            break
        fi
    done

    if [[ -n "$found_iso" ]]; then
        info "Найден ISO: $found_iso"
        extract_wim_from_iso "$found_iso" "Windows-Server2019"
        return 0
    fi

    read -r -p "Введите путь к ISO файлу (или URL, или Enter для пропуска): " user_input
    if [[ -z "$user_input" ]]; then
        warn "Пропущено"
        return 0
    fi

    if [[ "$user_input" == http* ]]; then
        download_iso "$user_input" "$iso_file" || return 1
        extract_wim_from_iso "$iso_file" "Windows-Server2019"
    elif [[ -f "$user_input" ]]; then
        extract_wim_from_iso "$user_input" "Windows-Server2019"
    else
        error "Файл не найден: $user_input"
        return 1
    fi
}

# ─────────────────────────────────────
# From local ISO
# ─────────────────────────────────────
from_local_iso() {
    local iso_path="$1"

    if [[ ! -f "$iso_path" ]]; then
        error "Файл не найден: $iso_path"
        exit 1
    fi

    local basename_lower
    basename_lower=$(basename "$iso_path" | tr '[:upper:]' '[:lower:]')

    local prefix="Windows"
    if [[ "$basename_lower" == *"2025"* ]]; then
        prefix="Windows-Server2025"
    elif [[ "$basename_lower" == *"2022"* ]]; then
        prefix="Windows-Server2022"
    elif [[ "$basename_lower" == *"2019"* ]]; then
        prefix="Windows-Server2019"
    elif [[ "$basename_lower" == *"2016"* ]]; then
        prefix="Windows-Server2016"
    elif [[ "$basename_lower" == *"win11"* || "$basename_lower" == *"windows_11"* || "$basename_lower" == *"windows11"* ]]; then
        prefix="Windows-11"
    elif [[ "$basename_lower" == *"win10"* || "$basename_lower" == *"windows_10"* || "$basename_lower" == *"windows10"* ]]; then
        prefix="Windows-10"
    else
        read -r -p "Не удалось определить версию. Введите префикс (например Windows-Server2022): " prefix
        [[ -z "$prefix" ]] && prefix="Windows"
    fi

    extract_wim_from_iso "$iso_path" "$prefix"
}

# ─────────────────────────────────────
# Show results
# ─────────────────────────────────────
show_results() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Доступные WIM-образы:${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo ""

    if [[ -d "$IMAGES_DIR" ]]; then
        local count=0
        while IFS= read -r -d '' wim; do
            local size
            size=$(du -h "$wim" | cut -f1)
            echo -e "  ${GREEN}✓${NC} $(basename "$wim") (${size})"
            ((count++)) || true
        done < <(find "$IMAGES_DIR" -maxdepth 1 -type f -name "*.wim" -print0 2>/dev/null)

        if ((count == 0)); then
            echo -e "  ${YELLOW}Нет WIM-образов${NC}"
        else
            echo ""
            echo -e "  Всего: $count образ(ов)"
            echo -e "  Путь:  $IMAGES_DIR"
        fi
    else
        echo -e "  ${YELLOW}Директория $IMAGES_DIR не существует${NC}"
    fi

    echo ""
    echo -e "${YELLOW}  Для установки Windows:${NC}"
    echo -e "    vdsok-install -a -i $IMAGES_DIR/<image>.wim -n hostname"
    echo ""
}

# ─────────────────────────────────────
# Interactive menu
# ─────────────────────────────────────
interactive_menu() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   VDSok — Windows Image Downloader       ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    echo "  Выберите образ для скачивания:"
    echo ""
    echo "  1) Windows Server 2025  (Datacenter/Standard)"
    echo "  2) Windows Server 2022  (Datacenter/Standard)"
    echo "  3) Windows Server 2019  (Datacenter/Standard)"
    echo "  4) Все серверные образы"
    echo "  5) Извлечь WIM из локального ISO"
    echo "  6) Показать имеющиеся образы"
    echo "  0) Выход"
    echo ""

    read -r -p "  Выбор [1-6]: " choice
    case "$choice" in
        1) download_server_2025 ;;
        2) download_server_2022 ;;
        3) download_server_2019 ;;
        4)
            download_server_2025
            download_server_2022
            download_server_2019
            ;;
        5)
            read -r -p "  Путь к ISO: " iso_path
            from_local_iso "$iso_path"
            ;;
        6) show_results; return ;;
        0) exit 0 ;;
        *) error "Неверный выбор"; exit 1 ;;
    esac

    show_results
}

# ─────────────────────────────────────
# Main
# ─────────────────────────────────────
main() {
    install_deps
    mkdir -p "$TEMP_DIR" "$IMAGES_DIR"

    case "${1:-}" in
        --server2022)    download_server_2022; show_results ;;
        --server2025)    download_server_2025; show_results ;;
        --server2019)    download_server_2019; show_results ;;
        --all)
            download_server_2025
            download_server_2022
            download_server_2019
            show_results
            ;;
        --from-iso)
            [[ -z "${2:-}" ]] && { error "Usage: $0 --from-iso /path/to/file.iso"; exit 1; }
            from_local_iso "$2"
            show_results
            ;;
        --list)          show_results ;;
        "")              interactive_menu ;;
        *)
            echo "Usage: $0 [--server2022|--server2025|--server2019|--all|--from-iso <path>|--list]"
            exit 1
            ;;
    esac
}

main "$@"
