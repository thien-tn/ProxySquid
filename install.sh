#!/usr/bin/env bash

# install.sh
#
# Script cài đặt và quản lý Squid HTTP proxy server
# Hỗ trợ Ubuntu, Debian và CentOS  
# Tác giả gốc: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP
#
# Script này cung cấp các chức năng:
# - Cài đặt Squid HTTP proxy server với xác thực
# - Quản lý proxy user (thêm, xóa, liệt kê)
# - Giới hạn bandwidth và quota cho từng user
# - Monitoring và thống kê sử dụng
# - Xuất danh sách proxy
# - Gỡ cài đặt Squid

# Nạp các module cần thiết
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/check_environment.sh"
source "$(dirname "$0")/lib/install_squid.sh"
source "$(dirname "$0")/lib/setup_service.sh"
source "$(dirname "$0")/lib/user_management.sh"
source "$(dirname "$0")/lib/uninstall.sh"

# Hiển thị banner
show_banner() {
    clear
    echo -e "${CYAN}=======================================================${NC}"
    echo -e "${GREEN}          Squid HTTP Proxy Server Manager             ${NC}"
    echo -e "${GREEN}                  Phiên bản 2.0                       ${NC}"
    echo -e "${CYAN}=======================================================${NC}"
    echo -e "${YELLOW}Tác giả gốc: akmaslov-dev (Dante version)${NC}"
    echo -e "${YELLOW}Chuyển đổi sang Squid bởi: ThienTranJP${NC}"
    echo -e "${CYAN}=======================================================${NC}"
    echo ""
}

# Hiển thị menu chính và xử lý lựa chọn
show_main_menu() {
    while true; do
        show_banner
        
        echo "Quản lý Squid HTTP Proxy:"
        echo -e "${CYAN}  1)${NC} Xem danh sách proxy hiện có"
        echo -e "${CYAN}  2)${NC} Thêm một proxy user mới"
        echo -e "${CYAN}  3)${NC} Thêm ngẫu nhiên nhiều proxy"
        echo -e "${CYAN}  4)${NC} Xóa một proxy user"
        echo -e "${CYAN}  5)${NC} Xóa toàn bộ proxy user"
        echo -e "${CYAN}  6)${NC} Cập nhật giới hạn bandwidth"
        echo -e "${CYAN}  7)${NC} Cập nhật quota dữ liệu"
        echo -e "${CYAN}  8)${NC} Xuất danh sách proxy"
        echo -e "${CYAN}  9)${NC} Xem thống kê và monitoring"
        echo -e "${CYAN} 10)${NC} Kiểm tra trạng thái dịch vụ"
        echo -e "${CYAN} 11)${NC} Khởi động lại dịch vụ"
        echo -e "${CYAN} 12)${NC} Backup database"
        echo -e "${RED} 13)${NC} Xóa toàn bộ cấu hình server proxy & user"
        echo -e "${CYAN} 14)${NC} Thoát"
        echo ""
        
        read -p "Chọn một tùy chọn [1-14]: " option
        
        case $option in
            1) list_proxy_users ;;
            2) add_proxy_user ;;
            3) add_random_proxies ;;
            4) delete_proxy_user ;;
            5) delete_all_proxy_users ;;
            6) update_user_bandwidth ;;
            7) update_user_quota ;;
            8) export_proxy_list ;;
            9) show_statistics ;;
            10) check_service_status ;;
            11) restart_service ;;
            12) backup_database ;;
            13) show_uninstall_menu ;;
            14) 
                echo "Đang thoát..."
                exit 0 
                ;;
            *) 
                error_message "Lựa chọn không hợp lệ"
                pause 
                ;;
        esac
    done
}

# Hàm main
main() {
    # Kiểm tra quyền root
    check_root
    
    # Kiểm tra bash shell
    check_bash
    
    # Phát hiện hệ điều hành
    detect_os
    
    # Phát hiện giao diện mạng
    detect_network_interface
    
    # Kiểm tra Squid đã được cài đặt chưa
    if is_squid_installed; then
        # Nếu đã cài đặt, hiển thị menu quản lý
        show_main_menu
    else
        # Nếu chưa cài đặt, tiến hành cài đặt
        show_banner
        info_message "Squid HTTP proxy server chưa được cài đặt."
        read -p "Bạn có muốn cài đặt Squid HTTP proxy server? (y/n): " -e -i y INSTALL
        
        if [[ "$INSTALL" == 'y' || "$INSTALL" == 'Y' ]]; then
            # Cài đặt Squid
            install_squid
            
            # Sau khi cài đặt, hiển thị menu quản lý
            show_main_menu
        else
            info_message "Đã hủy cài đặt. Thoát..."
            exit 0
        fi
    fi
}

# Chạy chương trình
main
