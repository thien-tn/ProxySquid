#!/usr/bin/env bash

# scripts/system_check.sh
#
# Script kiểm tra hệ thống cho Squid HTTP Proxy
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Lấy đường dẫn tuyệt đối của script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các module cần thiết
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/check_environment.sh"

# Hàm kiểm tra hệ thống
perform_system_check() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                              KIỂM TRA HỆ THỐNG                                   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    # Kiểm tra thông tin cơ bản
    echo -e "\n${YELLOW}1. Thông tin hệ thống:${NC}"
    echo -e "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Unknown")"
    echo -e "Kernel: $(uname -r)"
    echo -e "Architecture: $(uname -m)"
    echo -e "Hostname: $(hostname)"
    echo -e "Uptime: $(uptime -p 2>/dev/null || echo "Unknown")"
    
    # Kiểm tra tài nguyên hệ thống
    echo -e "\n${YELLOW}2. Tài nguyên hệ thống:${NC}"
    echo -e "CPU Cores: $(nproc)"
    echo -e "RAM: $(free -h | awk 'NR==2{printf "%s/%s (%.1f%%)", $3, $2, $3*100/$2}' 2>/dev/null || echo "Unknown")"
    echo -e "Disk Usage: $(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}' 2>/dev/null || echo "Unknown")"
    echo -e "Load Average: $(uptime | awk -F'load average:' '{print $2}' 2>/dev/null || echo "Unknown")"
    
    # Kiểm tra network
    echo -e "\n${YELLOW}3. Network:${NC}"
    local interface=$(ip -o -4 route show to default | awk '{print $5}' 2>/dev/null)
    echo -e "Default Interface: ${interface:-Unknown}"
    local server_ip=$(get_server_ip 2>/dev/null)
    echo -e "Public IP: ${server_ip:-Unknown}"
    
    # Kiểm tra Squid
    echo -e "\n${YELLOW}4. Squid HTTP Proxy:${NC}"
    if is_squid_installed; then
        echo -e "Status: ${GREEN}✓ Đã cài đặt${NC}"
        local squid_status=$(systemctl is-active squid 2>/dev/null || echo "unknown")
        if [[ "$squid_status" == "active" ]]; then
            echo -e "Service: ${GREEN}✓ Đang hoạt động${NC}"
        else
            echo -e "Service: ${RED}✗ Không hoạt động${NC}"
        fi
        
        local port=$(get_squid_port 2>/dev/null)
        echo -e "Port: ${port:-Unknown}"
        
        # Kiểm tra log files
        if [[ -f "/var/log/squid/access.log" ]]; then
            local log_size=$(du -h /var/log/squid/access.log 2>/dev/null | cut -f1)
            echo -e "Access Log: ${GREEN}✓${NC} (${log_size:-0})"
        else
            echo -e "Access Log: ${RED}✗ Không tìm thấy${NC}"
        fi
        
        # Kiểm tra config file
        if [[ -f "/etc/squid/squid.conf" ]]; then
            echo -e "Config File: ${GREEN}✓ Tồn tại${NC}"
            # Test config syntax
            if squid -k parse 2>/dev/null; then
                echo -e "Config Syntax: ${GREEN}✓ Hợp lệ${NC}"
            else
                echo -e "Config Syntax: ${RED}✗ Có lỗi${NC}"
            fi
        else
            echo -e "Config File: ${RED}✗ Không tìm thấy${NC}"
        fi
    else
        echo -e "Status: ${RED}✗ Chưa cài đặt${NC}"
    fi
    
    # Kiểm tra database
    echo -e "\n${YELLOW}5. Database:${NC}"
    if [[ -f "$DB_PATH" ]]; then
        echo -e "SQLite Database: ${GREEN}✓ Tồn tại${NC}"
        local db_size=$(du -h "$DB_PATH" 2>/dev/null | cut -f1)
        echo -e "Database Size: ${db_size:-Unknown}"
        
        # Kiểm tra số lượng users
        local user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
        echo -e "Total Users: $user_count"
        
        local active_users=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='active';" 2>/dev/null || echo "0")
        echo -e "Active Users: $active_users"
    else
        echo -e "SQLite Database: ${RED}✗ Không tìm thấy${NC}"
    fi
    
    # Kiểm tra dependencies
    echo -e "\n${YELLOW}6. Dependencies:${NC}"
    local packages=("squid" "sqlite3" "apache2-utils" "iptables" "tc")
    for package in "${packages[@]}"; do
        if command -v "$package" >/dev/null 2>&1; then
            echo -e "$package: ${GREEN}✓ Đã cài đặt${NC}"
        else
            echo -e "$package: ${RED}✗ Chưa cài đặt${NC}"
        fi
    done
    
    # Kiểm tra ports
    echo -e "\n${YELLOW}7. Network Ports:${NC}"
    if [[ -n "$port" ]]; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "Port $port: ${GREEN}✓ Đang lắng nghe${NC}"
        else
            echo -e "Port $port: ${RED}✗ Không lắng nghe${NC}"
        fi
    fi
    
    # Kiểm tra firewall
    echo -e "\n${YELLOW}8. Firewall:${NC}"
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null | head -1)
        echo -e "UFW: $ufw_status"
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(iptables -L INPUT 2>/dev/null | wc -l)
        echo -e "iptables rules: $((iptables_rules - 2))"
    fi
    
    # Kiểm tra traffic control
    echo -e "\n${YELLOW}9. Traffic Control:${NC}"
    if [[ -n "$interface" ]]; then
        if tc qdisc show dev "$interface" 2>/dev/null | grep -q "htb"; then
            echo -e "Traffic Control: ${GREEN}✓ Đã cấu hình${NC}"
        else
            echo -e "Traffic Control: ${RED}✗ Chưa cấu hình${NC}"
        fi
    fi
    
    echo -e "\n${GREEN}Kiểm tra hệ thống hoàn tất!${NC}"
    pause
}

# Hàm main
main() {
    # Kiểm tra quyền root
    if [[ $EUID -ne 0 ]]; then
        error_message "Script này cần chạy với quyền root"
        exit 1
    fi
    
    # Thực hiện kiểm tra hệ thống
    perform_system_check
}

# Chạy script
main "$@"
