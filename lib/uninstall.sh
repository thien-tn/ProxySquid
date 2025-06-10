#!/usr/bin/env bash

# lib/uninstall.sh
#
# Script gỡ cài đặt Squid HTTP proxy server và tất cả cấu hình
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Gỡ cài đặt hoàn toàn Squid proxy server
uninstall_squid() {
    warning_message "GỠ CÀI ĐẶT HOÀN TOÀN SQUID PROXY SERVER"
    echo ""
    echo -e "${RED}CẢNH BÁO: Thao tác này sẽ:${NC}"
    echo -e "${RED}• Xóa tất cả proxy users và cấu hình${NC}"
    echo -e "${RED}• Gỡ cài đặt Squid proxy server${NC}"
    echo -e "${RED}• Xóa tất cả dữ liệu và log files${NC}"
    echo -e "${RED}• Xóa database và backup files${NC}"
    echo -e "${RED}• Khôi phục cấu hình tường lửa mặc định${NC}"
    echo ""
    
    # Xác nhận lần 1
    read -p "Bạn có chắc chắn muốn gỡ cài đặt hoàn toàn? (y/n): " -e -i n confirm1
    
    if [[ "$confirm1" != 'y' && "$confirm1" != 'Y' ]]; then
        info_message "Đã hủy gỡ cài đặt"
        pause
        return 0
    fi
    
    # Xác nhận lần 2
    echo -e "${RED}XÁC NHẬN LẦN CUỐI:${NC}"
    read -p "Nhập 'UNINSTALL' để xác nhận gỡ cài đặt hoàn toàn: " final_confirm
    
    if [[ "$final_confirm" != "UNINSTALL" ]]; then
        info_message "Đã hủy gỡ cài đặt"
        pause
        return 0
    fi
    
    info_message "Bắt đầu gỡ cài đặt Squid proxy server..."
    
    # 1. Dừng và vô hiệu hóa dịch vụ
    info_message "Dừng dịch vụ Squid..."
    systemctl stop squid 2>/dev/null
    systemctl disable squid 2>/dev/null
    
    # Force kill all squid processes
    pkill -9 squid 2>/dev/null
    sleep 2
    
    # 2. Xóa tất cả users khỏi hệ thống
    info_message "Xóa tất cả proxy users..."
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "SELECT username FROM users;" 2>/dev/null | while read -r username; do
            if [[ -n "$username" ]]; then
                # Xóa system user nếu tồn tại
                userdel "$username" 2>/dev/null
                # Xóa home directory nếu tồn tại
                rm -rf "/home/$username" 2>/dev/null
            fi
        done
    fi
    
    # 3. Gỡ cài đặt packages
    info_message "Gỡ cài đặt Squid packages..."
    if [[ "$OStype" == "debian" || "$OStype" == "ubuntu" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y squid squid-common apache2-utils
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
        DEBIAN_FRONTEND=noninteractive apt-get autoclean
    elif [[ "$OStype" == "centos" ]]; then
        yum remove -y squid httpd-tools
        yum autoremove -y
    fi
    
    # 4. Xóa tất cả file cấu hình và dữ liệu
    info_message "Xóa file cấu hình và dữ liệu..."
    rm -rf /etc/squid
    rm -rf /var/cache/squid
    rm -rf /var/log/squid
    rm -rf /var/lib/proxy-manager
    rm -f "$PROXY_INFO_FILE"
    rm -f "$LOG_FILE"
    rm -f /root/proxy_backup_*.db
    rm -f /root/proxy_export_*.txt
    
    # 5. Xóa các traffic control rules
    info_message "Xóa traffic control rules..."
    local interface=$(ip -o -4 route show to default | awk '{print $5}' 2>/dev/null)
    if [[ -n "$interface" ]]; then
        tc qdisc del dev "$interface" root 2>/dev/null
    fi
    
    # 6. Khôi phục cấu hình tường lửa
    info_message "Khôi phục cấu hình tường lửa..."
    
    # Xóa rules iptables liên quan đến proxy
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t nat -X 2>/dev/null
    
    # Reset UFW rules nếu có
    if command -v ufw >/dev/null 2>&1; then
        ufw --force reset >/dev/null 2>&1
        ufw --force enable >/dev/null 2>&1
    fi
    
    # Lưu cấu hình iptables
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1
    fi
    
    # 7. Tắt IP forwarding
    info_message "Tắt IP forwarding..."
    echo 0 > /proc/sys/net/ipv4/ip_forward
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null
    sysctl -p >/dev/null 2>&1
    
    # 8. Xóa cron jobs liên quan
    info_message "Xóa cron jobs..."
    crontab -l 2>/dev/null | grep -v "squid" | crontab - 2>/dev/null
    
    # 9. Clear system caches
    info_message "Dọn dẹp system cache..."
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    # 10. Restart network service để áp dụng thay đổi
    info_message "Restart network services..."
    systemctl restart networking 2>/dev/null || systemctl restart network 2>/dev/null
    
    success_message "Gỡ cài đặt Squid proxy server hoàn tất!"
    
    echo ""
    echo -e "${GREEN}Đã hoàn thành các thao tác:${NC}"
    echo -e "• ✓ Dừng và gỡ cài đặt dịch vụ Squid"
    echo -e "• ✓ Xóa tất cả proxy users và cấu hình"
    echo -e "• ✓ Gỡ cài đặt packages liên quan"
    echo -e "• ✓ Xóa tất cả file dữ liệu và logs"
    echo -e "• ✓ Khôi phục cấu hình tường lửa"
    echo -e "• ✓ Xóa traffic control rules"
    echo -e "• ✓ Tắt IP forwarding"
    echo -e "• ✓ Dọn dẹp system cache"
    
    echo ""
    echo -e "${YELLOW}Lưu ý:${NC}"
    echo -e "• Máy chủ đã được khôi phục về trạng thái ban đầu"
    echo -e "• Tất cả dữ liệu proxy đã được xóa vĩnh viễn"
    echo -e "• Nếu muốn cài đặt lại, chạy lại script install.sh"
    
    pause
}

# Gỡ cài đặt nhẹ - chỉ xóa users và cấu hình
soft_uninstall() {
    warning_message "GỠ CÀI ĐẶT NHẸ - CHỈ XÓA USERS VÀ CẤU HÌNH"
    echo ""
    echo -e "${YELLOW}Thao tác này sẽ:${NC}"
    echo -e "• Xóa tất cả proxy users"
    echo -e "• Reset cấu hình Squid về mặc định"
    echo -e "• Xóa database và logs"
    echo -e "• Giữ lại Squid packages đã cài đặt"
    echo ""
    
    read -p "Bạn có muốn tiếp tục? (y/n): " -e -i n confirm
    
    if [[ "$confirm" != 'y' && "$confirm" != 'Y' ]]; then
        info_message "Đã hủy gỡ cài đặt nhẹ"
        pause
        return 0
    fi
    
    info_message "Bắt đầu gỡ cài đặt nhẹ..."
    
    # Dừng dịch vụ
    systemctl stop squid 2>/dev/null
    
    # Xóa users khỏi database
    if [[ -f "$DB_PATH" ]]; then
        rm -f "$DB_PATH"
    fi
    
    # Reset file password
    > /etc/squid/passwd 2>/dev/null
    
    # Xóa logs
    rm -rf /var/log/squid/* 2>/dev/null
    rm -f "$LOG_FILE"
    
    # Reset cấu hình Squid
    if [[ -f /etc/squid/squid.conf.bak ]]; then
        mv /etc/squid/squid.conf.bak /etc/squid/squid.conf
    fi
    
    # Khởi động lại dịch vụ
    systemctl start squid 2>/dev/null
    
    success_message "Gỡ cài đặt nhẹ hoàn thành!"
    
    pause
}

# Menu gỡ cài đặt
show_uninstall_menu() {
    while true; do
        clear
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                      GỠ CÀI ĐẶT PROXY                        ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}1)${NC} Gỡ cài đặt hoàn toàn (xóa tất cả)"
        echo -e "${CYAN}2)${NC} Gỡ cài đặt nhẹ (chỉ xóa users và cấu hình)"
        echo -e "${CYAN}3)${NC} Quay lại menu chính"
        echo ""
        
        read -p "Chọn tùy chọn [1-3]: " choice
        
        case $choice in
            1) uninstall_squid ;;
            2) soft_uninstall ;;
            3) return 0 ;;
            *) 
                error_message "Lựa chọn không hợp lệ"
                pause
                ;;
        esac
    done
}
