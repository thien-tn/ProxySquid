#!/usr/bin/env bash

# lib/install_squid.sh
#
# Module cài đặt và cấu hình Squid HTTP Proxy
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP
# Dựa trên squid-proxy-manager.sh

# Hàm dọn dẹp cài đặt cũ
cleanup_old_installation() {
    info_message "Đang dọn dẹp cài đặt cũ..."
    
    # Force kill tất cả các process liên quan
    pkill -9 squid 2>/dev/null
    pkill -9 tc 2>/dev/null
    sleep 2
    
    # Dừng và disable services
    systemctl stop squid 2>/dev/null
    systemctl disable squid 2>/dev/null
    sleep 2
    
    # Remove packages với force
    export DEBIAN_FRONTEND=noninteractive
    apt-get remove --purge -y squid squid-common apache2-utils sqlite3 2>/dev/null
    apt-get autoremove -y 2>/dev/null
    apt-get clean 2>/dev/null
    
    # Xóa tất cả thư mục và file liên quan
    rm -rf /etc/squid
    rm -rf /var/lib/proxy-manager
    rm -rf /var/log/squid
    rm -rf /var/cache/squid
    rm -rf /var/spool/squid
    rm -f "$PROXY_INFO_FILE"
    rm -f "$LOG_FILE"
    
    # Dọn dẹp network rules
    local interface=$(detect_network_interface)
    tc qdisc del dev "$interface" root 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t nat -X 2>/dev/null
    
    # Clear system caches
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    # Reset proxy settings
    unset http_proxy https_proxy
    
    success_message "Dọn dẹp cài đặt cũ hoàn tất"
    sleep 2
}

# Hàm chuẩn bị hệ thống
prepare_system() {
    info_message "Đang chuẩn bị hệ thống..."
    
    # Disable interactive prompts
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package list với timeout
    info_message "Đang cập nhật danh sách gói..."
    timeout 300 apt-get update || {
        warning_message "Update gói có thể chậm, tiếp tục cài đặt..."
    }
    
    # Cài đặt các gói cơ bản
    local essential_packages=(
        "software-properties-common"
        "curl"
        "wget"
        "net-tools"
        "ca-certificates"
        "gnupg"
        "lsb-release"
    )
    
    for package in "${essential_packages[@]}"; do
        info_message "Đang cài đặt $package..."
        timeout 300 apt-get install -y "$package" || {
            warning_message "Không thể cài đặt $package, tiếp tục..."
        }
    done
    
    # Add universe repository
    add-apt-repository universe -y 2>/dev/null
    
    # Update lại sau khi add repo
    timeout 300 apt-get update || {
        warning_message "Update sau khi add repo có thể chậm..."
    }
    
    success_message "Chuẩn bị hệ thống hoàn tất"
}

# Hàm cài đặt dependencies
install_dependencies() {
    info_message "Đang cài đặt các gói phụ thuộc..."
    
    # Danh sách các gói cần thiết
    local packages=(
        "squid"
        "apache2-utils"
        "sqlite3"
        "libsqlite3-dev"
        "iptables-persistent"
        "net-tools"
        "curl"
        "wget"
        "htop"
        "ufw"
        "iproute2"
        "netfilter-persistent"
    )
    
    # Cài đặt từng gói một
    for package in "${packages[@]}"; do
        info_message "Đang cài đặt $package..."
        
        if ! timeout 300 apt-get install -y "$package"; then
            error_message "Không thể cài đặt $package"
            return 1
        fi
        
        # Kiểm tra package đã được cài đặt chưa
        if ! dpkg -l | grep -q "^ii.*$package"; then
            error_message "Package $package không được cài đặt đúng"
            return 1
        fi
        
        success_message "Đã cài đặt $package thành công"
    done
    
    success_message "Tất cả dependencies đã được cài đặt"
    return 0
}

# Hàm thiết lập database
setup_database() {
    info_message "Đang thiết lập SQLite database..."
    
    # Tạo thư mục cho database
    mkdir -p "$(dirname "$DB_PATH")"
    
    # Tạo database với schema
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    bandwidth_limit INTEGER DEFAULT 0,
    data_quota INTEGER DEFAULT 0,
    data_used INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_active DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS traffic_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    bytes_in INTEGER DEFAULT 0,
    bytes_out INTEGER DEFAULT 0,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(username) REFERENCES users(username)
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_traffic_username ON traffic_log(username);
CREATE INDEX IF NOT EXISTS idx_traffic_timestamp ON traffic_log(timestamp);
EOF
    
    # Đặt quyền cho database
    chmod 600 "$DB_PATH"
    
    success_message "Database đã được thiết lập"
    return 0
}

# Hàm cấu hình Squid
configure_squid() {
    info_message "Đang cấu hình Squid proxy..."
    
    # Dừng service nếu đang chạy
    systemctl stop squid 2>/dev/null
    systemctl disable squid 2>/dev/null
    
    # Tạo thư mục cần thiết
    mkdir -p /etc/squid
    mkdir -p /var/log/squid
    mkdir -p /var/cache/squid
    mkdir -p /var/spool/squid
    
    # Backup file cấu hình cũ nếu có
    if [[ -f /etc/squid/squid.conf ]]; then
        mv /etc/squid/squid.conf /etc/squid/squid.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Lấy port từ config hoặc sử dụng mặc định
    local proxy_port="${SQUID_PORT:-8080}"
    
    # Tạo file cấu hình Squid mới
    cat > /etc/squid/squid.conf <<EOF
# Cấu hình Squid HTTP Proxy
# Được tạo bởi: Squid Proxy Manager
# Ngày tạo: $(date '+%Y-%m-%d %H:%M:%S')

# Cấu hình Network
http_port ${proxy_port}
visible_hostname squid-proxy-server

# Cấu hình Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm "Proxy Authentication Required"
auth_param basic credentialsttl 30 days
auth_param basic casesensitive off

# Access Control Lists
acl authenticated proxy_auth REQUIRED
acl CONNECT method CONNECT

# Quy tắc truy cập
http_access allow authenticated
http_access allow localhost manager
http_access deny manager
http_access deny all

# DNS Configuration
dns_v4_first on
dns_nameservers 8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1

# Performance Settings
maximum_object_size 128 MB
cache_mem 256 MB
cache_dir ufs /var/spool/squid 1000 16 256
pipeline_prefetch on

# Logging Configuration
access_log /var/log/squid/access.log combined
cache_log /var/log/squid/cache.log
pid_filename /var/run/squid.pid

# Timeout Settings
connect_timeout 1 minute
peer_connect_timeout 30 seconds
read_timeout 5 minutes
request_timeout 5 minutes

# Privacy Settings - Ẩn thông tin client
forwarded_for off
via off

# Security Headers - Chỉ cho phép các header cần thiết
request_header_access Allow allow all
request_header_access Authorization allow all
request_header_access WWW-Authenticate allow all
request_header_access Proxy-Authorization allow all
request_header_access Proxy-Authenticate allow all
request_header_access Cache-Control allow all
request_header_access Content-Encoding allow all
request_header_access Content-Length allow all
request_header_access Content-Type allow all
request_header_access Date allow all
request_header_access Expires allow all
request_header_access Host allow all
request_header_access If-Modified-Since allow all
request_header_access Last-Modified allow all
request_header_access Location allow all
request_header_access Pragma allow all
request_header_access Accept allow all
request_header_access Accept-Charset allow all
request_header_access Accept-Encoding allow all
request_header_access Accept-Language allow all
request_header_access Content-Language allow all
request_header_access Mime-Version allow all
request_header_access Retry-After allow all
request_header_access Title allow all
request_header_access Connection allow all
request_header_access Proxy-Connection allow all
request_header_access User-Agent allow all
request_header_access Cookie allow all
request_header_access All deny all

# Bảo mật bổ sung - Ẩn header tracking
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access X-Real-IP deny all
request_header_access X-Originating-IP deny all

# Cache settings
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# Error page
error_directory /usr/share/squid/errors/English
EOF
    
    # Tạo file password cho authentication
    touch /etc/squid/passwd
    
    # Đặt ownership và permissions đúng
    chown -R proxy:proxy /etc/squid /var/log/squid /var/cache/squid /var/spool/squid
    chmod 644 /etc/squid/passwd
    chmod 755 /etc/squid
    chmod 755 /var/log/squid
    chmod 755 /var/cache/squid
    chmod 755 /var/spool/squid
    
    # Khởi tạo cache directories
    squid -z 2>/dev/null || {
        warning_message "Không thể khởi tạo cache directory, tiếp tục..."
    }
    
    # Kiểm tra cú pháp cấu hình
    if ! squid -k parse 2>/dev/null; then
        error_message "File cấu hình Squid có lỗi cú pháp"
        squid -k parse
        return 1
    fi
    
    success_message "Cấu hình Squid hoàn tất"
    return 0
}

# Hàm thiết lập networking
setup_networking() {
    info_message "Đang cấu hình network..."
    
    # Lấy interface và port
    local interface=$(detect_network_interface)
    local proxy_port="${SQUID_PORT:-8080}"
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
    
    # Configure UFW
    ufw --force enable >/dev/null 2>&1
    ufw allow "$proxy_port"/tcp >/dev/null 2>&1
    
    # Configure iptables
    iptables -t nat -A POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null
    iptables -A INPUT -p tcp --dport "$proxy_port" -j ACCEPT 2>/dev/null
    
    # Save iptables rules
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1
        netfilter-persistent reload >/dev/null 2>&1
    fi
    
    success_message "Cấu hình network hoàn tất"
    return 0
}

# Hàm thiết lập traffic control
setup_traffic_control() {
    info_message "Đang thiết lập traffic control..."
    
    local interface=$(detect_network_interface)
    
    # Xóa qdisc cũ nếu có
    tc qdisc del dev "$interface" root 2>/dev/null
    
    # Thêm root qdisc với HTB
    tc qdisc add dev "$interface" root handle 1: htb default 10
    tc class add dev "$interface" parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit
    tc class add dev "$interface" parent 1:1 classid 1:10 htb rate 1000mbit ceil 1000mbit
    
    success_message "Traffic control đã được cấu hình"
    return 0
}

# Hàm khởi động dịch vụ
start_squid_service() {
    info_message "Đang khởi động dịch vụ Squid..."
    
    # Enable và start service
    systemctl enable squid
    
    if systemctl start squid; then
        success_message "Đã khởi động dịch vụ Squid thành công"
        
        # Kiểm tra trạng thái sau 3 giây
        sleep 3
        if systemctl is-active --quiet squid; then
            success_message "Dịch vụ Squid đang hoạt động bình thường"
            
            # Hiển thị thông tin port
            local port=$(get_squid_port)
            if [[ -n "$port" ]]; then
                info_message "Squid đang lắng nghe trên port: $port"
            fi
        else
            warning_message "Dịch vụ Squid có thể gặp vấn đề"
            systemctl status squid
        fi
    else
        error_message "Không thể khởi động dịch vụ Squid"
        info_message "Chi tiết lỗi:"
        systemctl status squid
        journalctl -xeu squid.service | tail -20
        return 1
    fi
    
    return 0
}

# Hàm tạo user ban đầu
create_initial_user() {
    info_message "Đang tạo user proxy ban đầu..."
    
    # Tạo random credentials
    local username=$(openssl rand -base64 8 | tr -dc 'a-zA-Z' | head -c 8)
    local password=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    
    # Tạo system user với group ngẫu nhiên
    local random_group="proxy$(date +%s)"
    groupadd "$random_group" 2>/dev/null || true
    useradd -M -s /usr/sbin/nologin -g "$random_group" "$username" 2>/dev/null || true
    
    # Đặt password
    echo "$username:$password" | chpasswd
    
    # Thêm vào Squid
    htpasswd -b /etc/squid/passwd "$username" "$password"
    
    # Thêm vào database
    sqlite3 "$DB_PATH" "INSERT INTO users (username, password) VALUES ('$username', '$password');" 2>/dev/null
    
    # Lưu thông tin proxy
    local server_ip=$(get_server_ip)
    local proxy_port=$(get_squid_port)
    
    cat > "$PROXY_INFO_FILE" <<EOF
=============================================
Thông Tin Proxy (Tạo: $(date '+%Y-%m-%d %H:%M:%S'))
=============================================
Username: $username
Password: $password
Proxy IP: $server_ip
Port: $proxy_port
=============================================
Proxy String: $username:$password@$server_ip:$proxy_port
=============================================
EOF
    
    chmod 600 "$PROXY_INFO_FILE"
    
    success_message "User ban đầu đã được tạo"
    echo -e "\n${GREEN}Thông tin tài khoản proxy:${NC}"
    echo -e "Username: ${YELLOW}$username${NC}"
    echo -e "Password: ${YELLOW}$password${NC}"
    echo -e "Proxy IP: ${YELLOW}$server_ip${NC}"
    echo -e "Port: ${YELLOW}$proxy_port${NC}"
    echo -e "Proxy String: ${YELLOW}$username:$password@$server_ip:$proxy_port${NC}"
    
    return 0
}

# Hàm cài đặt chính
install_squid() {
    info_message "Bắt đầu cài đặt Squid HTTP Proxy..."
    
    # Kiểm tra quyền root
    if [[ $EUID -ne 0 ]]; then
        error_message "Script này cần chạy với quyền root"
        return 1
    fi
    
    # Kiểm tra hệ điều hành
    detect_os
    if [[ "$OStype" != "debian" ]]; then
        error_message "Script này chỉ hỗ trợ hệ điều hành Debian/Ubuntu"
        return 1
    fi
    
    # Kiểm tra network interface
    local interface=$(detect_network_interface)
    if [[ -z "$interface" ]]; then
        error_message "Không thể xác định network interface"
        return 1
    fi
    
    info_message "Hệ điều hành: $OStype"
    info_message "Network interface: $interface"
    
    # Thực hiện các bước cài đặt
    local steps=(
        "cleanup_old_installation"
        "prepare_system"
        "install_dependencies"
        "setup_database"
        "configure_squid"
        "setup_networking"
        "setup_traffic_control"
        "start_squid_service"
        "create_initial_user"
    )
    
    local total_steps=${#steps[@]}
    local current_step=0
    
    for step in "${steps[@]}"; do
        ((current_step++))
        info_message "Bước $current_step/$total_steps: Đang thực hiện $step..."
        
        # Thực hiện step và kiểm tra kết quả
        if $step; then
            success_message "Hoàn thành bước $current_step/$total_steps: $step"
        else
            local exit_code=$?
            error_message "Lỗi trong bước: $step (exit code: $exit_code)"
            
            # Hiển thị thêm debug info
            echo -e "\n${RED}=== DEBUG INFO ===${NC}"
            echo "Step failed: $step"
            echo "Exit code: $exit_code"
            echo "Current directory: $(pwd)"
            echo "User: $(whoami)"
            echo "OS Type: $OStype"
            echo "Interface: $interface"
            echo -e "${RED}==================${NC}\n"
            
            return 1
        fi
        
        echo ""
    done
    
    # Thông báo hoàn thành
    success_message "Cài đặt Squid HTTP Proxy hoàn tất!"
    echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                              CÀI ĐẶT HOÀN TẤT                                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${YELLOW}Thông tin quan trọng:${NC}"
    echo -e "• File cấu hình: ${CYAN}/etc/squid/squid.conf${NC}"
    echo -e "• Database: ${CYAN}$DB_PATH${NC}"
    echo -e "• Thông tin proxy: ${CYAN}$PROXY_INFO_FILE${NC}"
    echo -e "• Log file: ${CYAN}/var/log/squid/access.log${NC}"
    
    echo -e "\n${YELLOW}Lệnh hữu ích:${NC}"
    echo -e "• Xem thông tin proxy: ${CYAN}cat $PROXY_INFO_FILE${NC}"
    echo -e "• Kiểm tra trạng thái: ${CYAN}systemctl status squid${NC}"
    echo -e "• Xem log: ${CYAN}tail -f /var/log/squid/access.log${NC}"
    echo -e "• Restart service: ${CYAN}systemctl restart squid${NC}"
    
    # Tạo cron job dọn dẹp log
    (crontab -l 2>/dev/null; echo "0 0 * * * find /var/log/squid -mtime +7 -type f -delete") | crontab - 2>/dev/null
    
    info_message "Cài đặt hoàn tất. Squid proxy server đã sẵn sàng sử dụng."
    
    return 0
}
