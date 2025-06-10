#!/usr/bin/env bash

# scripts/uninstall.sh
#
# Script gỡ cài đặt Squid HTTP Proxy với menu lựa chọn
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Lấy đường dẫn tuyệt đối của script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các module cần thiết
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/uninstall.sh"

# Hàm main
main() {
    # Kiểm tra quyền root
    if [[ $EUID -ne 0 ]]; then
        error_message "Script này cần chạy với quyền root"
        exit 1
    fi
    
    # Kiểm tra Squid đã được cài đặt chưa
    if ! is_squid_installed; then
        error_message "Squid chưa được cài đặt."
        exit 1
    fi
    
    # Hiển thị menu gỡ cài đặt
    show_uninstall_menu
}

# Chạy script
main "$@"
