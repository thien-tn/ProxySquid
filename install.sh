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

# Hàm test các function cơ bản
test_basic_functions() {
    info_message "Đang test các function cơ bản..."
    
    echo -e "\n${YELLOW}=== KIỂM TRA CÁC FUNCTION ===${NC}"
    
    # Test detect_os
    echo -n "detect_os: "
    if detect_os >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC} (OS: $OStype)"
    else
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
    
    # Test detect_network_interface
    echo -n "detect_network_interface: "
    local test_interface=$(detect_network_interface)
    if [[ -n "$test_interface" ]]; then
        echo -e "${GREEN}OK${NC} (Interface: $test_interface)"
    else
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
    
    # Test check_root
    echo -n "check_root: "
    if [[ $EUID -eq 0 ]]; then
        echo -e "${GREEN}OK${NC} (Running as root)"
    else
        echo -e "${RED}FAIL${NC} (Not root)"
        return 1
    fi
    
    # Test required commands
    local required_commands=("apt-get" "systemctl" "sqlite3" "openssl")
    for cmd in "${required_commands[@]}"; do
        echo -n "Command $cmd: "
        if command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}MISSING${NC}"
        fi
    done
    
    echo -e "${YELLOW}=============================${NC}\n"
    
    success_message "Kiểm tra function cơ bản hoàn tất"
    return 0
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
    info_message "Đang kiểm tra trạng thái cài đặt Squid..."
    
    if is_squid_installed; then
        # Nếu đã cài đặt, hiển thị menu quản lý
        success_message "Squid đã được cài đặt, chuyển đến menu quản lý..."
        debug_squid_status
        pause
        show_main_menu
    else
        # Nếu chưa cài đặt, tiến hành cài đặt
        warning_message "Squid HTTP proxy server chưa được cài đặt."
        debug_squid_status
        
        show_banner
        info_message "Squid HTTP proxy server chưa được cài đặt."
        read -p "Bạn có muốn cài đặt Squid HTTP proxy server? (y/n): " -e -i y INSTALL
        
        if [[ "$INSTALL" == 'y' || "$INSTALL" == 'Y' ]]; then
            info_message "Bắt đầu quá trình cài đặt Squid..."
            
            # Test các function cơ bản trước
            if ! test_basic_functions; then
                error_message "Kiểm tra function cơ bản thất bại!"
                exit 1
            fi
            
            # Kiểm tra môi trường trước khi cài đặt
            info_message "Đang kiểm tra môi trường hệ thống..."
            
            # Cài đặt Squid với error handling
            if install_squid; then
                success_message "Cài đặt Squid thành công!"
                pause
                
                # Sau khi cài đặt thành công, hiển thị menu quản lý
                show_main_menu
            else
                error_message "Cài đặt Squid không thành công!"
                error_message "Vui lòng kiểm tra lỗi ở trên và thử lại."
                
                # Hiển thị thông tin debug
                echo -e "\n${YELLOW}Thông tin debug:${NC}"
                echo "- OS: $OStype"
                echo "- Interface: $(detect_network_interface)"
                echo "- User: $(whoami)"
                echo "- Squid installed: $(is_squid_installed && echo "Yes" || echo "No")"
                
                read -p "Nhấn Enter để thoát..."
                exit 1
            fi
        else
            info_message "Đã hủy cài đặt. Thoát..."
            exit 0
        fi
    fi
}

# Chạy chương trình
main
