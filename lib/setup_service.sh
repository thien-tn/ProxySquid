#!/usr/bin/env bash

# lib/setup_service.sh
#
# Chứa các hàm thiết lập dịch vụ Squid HTTP Proxy
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Tạo và khởi động dịch vụ Squid
create_service() {
    info_message "Đang khởi động dịch vụ Squid..."
    
    # Kiểm tra xem Squid đã được cài đặt chưa
    if ! command -v squid >/dev/null 2>&1; then
        error_message "Squid chưa được cài đặt trên hệ thống"
        return 1
    fi
    
    # Kiểm tra file cấu hình
    if [[ ! -f /etc/squid/squid.conf ]]; then
        error_message "Không tìm thấy file cấu hình /etc/squid/squid.conf"
        return 1
    fi
    
    # Kiểm tra cú pháp cấu hình
    info_message "Đang kiểm tra cú pháp cấu hình Squid..."
    if ! squid -k parse 2>/dev/null; then
        error_message "File cấu hình Squid có lỗi cú pháp"
        info_message "Chi tiết lỗi:"
        squid -k parse
        return 1
    fi
    
    # Khởi động và enable dịch vụ
    info_message "Đang khởi động dịch vụ Squid..."
    systemctl enable squid
    
    if systemctl start squid; then
        success_message "Đã khởi động dịch vụ Squid thành công"
        
        # Kiểm tra trạng thái
        sleep 2
        if systemctl is-active --quiet squid; then
            success_message "Dịch vụ Squid đang hoạt động bình thường"
        else
            warning_message "Dịch vụ Squid có thể gặp vấn đề"
            systemctl status squid
        fi
    else
        error_message "Không thể khởi động dịch vụ Squid"
        info_message "Chi tiết lỗi:"
        systemctl status squid
        journalctl -xeu squid.service
        return 1
    fi
}

# Dừng dịch vụ Squid
stop_service() {
    info_message "Đang dừng dịch vụ Squid..."
    
    if systemctl is-active --quiet squid; then
        systemctl stop squid
        success_message "Dịch vụ Squid đã được dừng"
    else
        warning_message "Dịch vụ Squid không đang chạy"
    fi
}

# Khởi động lại dịch vụ Squid
restart_service() {
    info_message "Đang khởi động lại dịch vụ Squid..."
    
    # Kiểm tra cú pháp cấu hình trước khi restart
    if ! squid -k parse 2>/dev/null; then
        error_message "File cấu hình Squid có lỗi, không thể khởi động lại"
        squid -k parse
        return 1
    fi
    
    systemctl restart squid
    
    # Đợi một chút để dịch vụ khởi động
    sleep 3
    
    if systemctl is-active --quiet squid; then
        success_message "Dịch vụ Squid đã được khởi động lại thành công"
        
        # Hiển thị thông tin port
        local port=$(get_squid_port)
        if [[ -n "$port" ]]; then
            info_message "Squid đang lắng nghe trên port: $port"
        fi
    else
        error_message "Không thể khởi động lại dịch vụ Squid"
        systemctl status squid
        journalctl -xeu squid.service
        return 1
    fi
}

# Kiểm tra trạng thái dịch vụ Squid
check_service_status() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        TRẠNG THÁI DỊCH VỤ SQUID                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    
    # Kiểm tra trạng thái systemd
    echo -e "\n${YELLOW}1. Trạng thái SystemD:${NC}"
    if systemctl is-active --quiet squid; then
        echo -e "   Status: ${GREEN}✓ Đang hoạt động${NC}"
    else
        echo -e "   Status: ${RED}✗ Không hoạt động${NC}"
    fi
    
    if systemctl is-enabled --quiet squid 2>/dev/null; then
        echo -e "   Auto Start: ${GREEN}✓ Được bật${NC}"
    else
        echo -e "   Auto Start: ${RED}✗ Bị tắt${NC}"
    fi
    
    # Hiển thị thông tin port
    echo -e "\n${YELLOW}2. Thông tin Network:${NC}"
    local port=$(get_squid_port)
    if [[ -n "$port" ]]; then
        echo -e "   Proxy Port: $port"
        
        # Kiểm tra port có đang lắng nghe không
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "   Port Status: ${GREEN}✓ Đang lắng nghe${NC}"
        else
            echo -e "   Port Status: ${RED}✗ Không lắng nghe${NC}"
        fi
    else
        echo -e "   Proxy Port: ${RED}✗ Không xác định${NC}"
    fi
    
    # Hiển thị thông tin process
    echo -e "\n${YELLOW}3. Process Information:${NC}"
    local squid_pid=$(pgrep -f squid 2>/dev/null | head -1)
    if [[ -n "$squid_pid" ]]; then
        echo -e "   PID: $squid_pid"
        local memory=$(ps -p "$squid_pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
        echo -e "   Memory: $memory"
        
        local uptime=$(ps -p "$squid_pid" -o etime= 2>/dev/null | sed 's/^ *//')
        echo -e "   Uptime: $uptime"
    else
        echo -e "   Process: ${RED}✗ Không tìm thấy${NC}"
    fi
    
    # Hiển thị log gần đây
    echo -e "\n${YELLOW}4. Recent Logs:${NC}"
    if [[ -f "/var/log/squid/access.log" ]]; then
        local log_size=$(du -h /var/log/squid/access.log 2>/dev/null | cut -f1)
        echo -e "   Access Log: ${GREEN}✓${NC} ($log_size)"
        
        # Hiển thị 3 dòng log gần nhất
        local recent_logs=$(tail -3 /var/log/squid/access.log 2>/dev/null)
        if [[ -n "$recent_logs" ]]; then
            echo -e "   Recent entries:"
            echo "$recent_logs" | sed 's/^/     /'
        fi
    else
        echo -e "   Access Log: ${RED}✗ Không tìm thấy${NC}"
    fi
    
    # Hiển thị systemctl status
    echo -e "\n${YELLOW}5. SystemD Status:${NC}"
    systemctl status squid --no-pager -l
    
    pause
}

# Reload cấu hình Squid
reload_config() {
    info_message "Đang reload cấu hình Squid..."
    
    # Kiểm tra cú pháp cấu hình trước
    if ! squid -k parse 2>/dev/null; then
        error_message "File cấu hình có lỗi, không thể reload"
        squid -k parse
        return 1
    fi
    
    # Reload cấu hình
    if systemctl reload squid; then
        success_message "Đã reload cấu hình Squid thành công"
    else
        error_message "Không thể reload cấu hình Squid"
        systemctl status squid
        return 1
    fi
}

# Gỡ bỏ dịch vụ Squid
remove_service() {
    info_message "Đang gỡ bỏ dịch vụ Squid..."
    
    # Dừng dịch vụ
    stop_service
    
    # Vô hiệu hóa dịch vụ
    systemctl disable squid 2>/dev/null
    
    success_message "Đã gỡ bỏ dịch vụ Squid"
}
