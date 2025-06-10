#!/usr/bin/env bash

# scripts/export_proxy_list.sh
#
# Script xuất danh sách proxy cho Squid HTTP Proxy
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Lấy đường dẫn tuyệt đối của script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các module cần thiết
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/user_management.sh"

# Hàm main
main() {
    # Kiểm tra quyền root
    if [[ $EUID -ne 0 ]]; then
        error_message "Script này cần chạy với quyền root"
        exit 1
    fi
    
    # Kiểm tra Squid đã được cài đặt chưa
    if ! is_squid_installed; then
        error_message "Squid chưa được cài đặt. Vui lòng chạy script cài đặt chính."
        exit 1
    fi
    
    # Đảm bảo database tồn tại
    if [[ ! -f "$DB_PATH" ]]; then
        setup_database
    fi
    
    # Gọi hàm export proxy list từ module user_management
    export_proxy_list
}

# Chạy script
main "$@"
