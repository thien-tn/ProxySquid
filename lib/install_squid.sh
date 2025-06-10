#!/usr/bin/env bash

# lib/install_squid.sh
#
# Chứa các hàm cài đặt Squid HTTP proxy server
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Cài đặt các gói phụ thuộc
install_dependencies() {
    info_message "Đang cài đặt các gói phụ thuộc..."
    
    # Disable interactive prompts
    export DEBIAN_FRONTEND=noninteractive
    
    if [[ "$OStype" == "debian" || "$OStype" == "ubuntu" ]]; then
        # Update package list
        apt-get update
        
        # Install essential packages one by one
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
            "openssl"
            "unattended-upgrades"
        )

        for package in "${packages[@]}"; do
            info_message "Đang cài đặt $package..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
            if ! dpkg -l | grep -q "^ii  $package"; then
                error_message "Không thể cài đặt $package"
                exit 1
            fi
        done
        
    elif [[ "$OStype" == "centos" ]]; then
        yum -y update
        yum -y install squid httpd-tools sqlite sqlite-devel iptables-services net-tools curl wget htop openssl
    fi
    
    success_message "Đã cài đặt tất cả các gói phụ thuộc"
}

# Dọn dẹp cài đặt cũ
cleanup_old_installation() {
    info_message "Dọn dẹp cài đặt cũ..."
    
    # Force kill all related processes
    pkill -9 squid 2>/dev/null
    pkill -9 tc 2>/dev/null
    sleep 2
    
    # Stop and disable services
    systemctl stop squid 2>/dev/null
    systemctl disable squid 2>/dev/null
    sleep 2
    
    # Remove old config and data
    rm -rf /etc/squid/squid.conf.bak 2>/dev/null
    rm -rf /var/cache/squid/* 2>/dev/null
    rm -f /var/log/squid/access.log* 2>/dev/null
    rm -f /var/log/squid/cache.log* 2>/dev/null
    
    # Clean up network rules
    local interface=$(ip -o -4 route show to default | awk '{print $5}')
    tc qdisc del dev "$interface" root 2>/dev/null
    
    # Clear system caches
    sync
    echo 3 > /proc/sys/vm/drop_caches
    
    success_message "Hoàn thành dọn dẹp"
}

# Tạo file cấu hình squid.conf
create_config() {
    info_message "Đang tạo file cấu hình /etc/squid/squid.conf..."
    
    # Backup old config if exists
    if [[ -f /etc/squid/squid.conf ]]; then
        mv /etc/squid/squid.conf /etc/squid/squid.conf.bak
    fi
    
    # Create new config based on template or from scratch
    if [[ -f "$CONFIG_DIR/squid.conf.template" ]]; then
        info_message "Sử dụng file template cấu hình..."
        cp "$CONFIG_DIR/squid.conf.template" /etc/squid/squid.conf
        
        # Thay thế các biến trong template
        sed -i "s/%PORT%/${port}/g" /etc/squid/squid.conf
        sed -i "s/%INTERFACE%/${interface}/g" /etc/squid/squid.conf
    else
        # Tạo file cấu hình trực tiếp
        cat > /etc/squid/squid.conf <<EOF
# Cấu hình cổng HTTP proxy
http_port ${port}
visible_hostname proxy-server

# Cấu hình xác thực cơ bản
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy Authentication Required
auth_param basic credentialsttl 30 days
auth_param basic casesensitive off
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Thiết lập DNS
dns_v4_first on
dns_nameservers 8.8.8.8 8.8.4.4

# Cấu hình hiệu suất
maximum_object_size 128 MB
cache_mem 256 MB
pipeline_prefetch on

# Cấu hình logging
access_log /var/log/squid/access.log combined
cache_log /var/log/squid/cache.log
pid_filename /var/run/squid.pid

# Cấu hình timeout
connect_timeout 1 minute
peer_connect_timeout 30 seconds
read_timeout 5 minutes
request_timeout 5 minutes

# Cấu hình bảo mật
forwarded_for off
via off

# Cho phép các header cần thiết
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

# Ẩn thông tin proxy
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
EOF
    fi
    
    # Tạo file mật khẩu trống
    touch /etc/squid/passwd
    chown proxy:proxy /etc/squid/passwd 2>/dev/null || chown squid:squid /etc/squid/passwd
    chmod 644 /etc/squid/passwd
    
    # Kiểm tra file cấu hình
    if [[ -f /etc/squid/squid.conf ]]; then
        success_message "Đã tạo file cấu hình /etc/squid/squid.conf"
        
        # Kiểm tra cú pháp file cấu hình
        if command -v squid >/dev/null 2>&1; then
            info_message "Kiểm tra cú pháp file cấu hình..."
            squid -k parse 2>/dev/null || {
                warning_message "File cấu hình có thể có lỗi cú pháp, nhưng vẫn tiếp tục..."
            }
        fi
    else
        error_message "Không thể tạo file cấu hình /etc/squid/squid.conf"
        exit 1
    fi
}

# Thiết lập dịch vụ systemd
setup_systemd_service() {
    info_message "Thiết lập dịch vụ systemd cho Squid..."
    
    # Enable and start squid service
    systemctl enable squid
    systemctl daemon-reload
    
    # Start squid service
    systemctl start squid
    sleep 3
    
    # Check if service is running
    if systemctl is-active --quiet squid; then
        success_message "Dịch vụ Squid đã khởi động thành công"
    else
        error_message "Không thể khởi động dịch vụ Squid"
        systemctl status squid
        exit 1
    fi
}

# Cấu hình mạng và tường lửa
setup_networking() {
    info_message "Cấu hình mạng và tường lửa..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    
    # Configure UFW if available
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$port"/tcp >/dev/null 2>&1
    fi
    
    # Configure iptables
    local interface=$(ip -o -4 route show to default | awk '{print $5}')
    iptables -t nat -A POSTROUTING -o "$interface" -j MASQUERADE >/dev/null 2>&1
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
    
    # Save iptables rules if available
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1
    fi
    
    success_message "Hoàn thành cấu hình mạng"
}

# Thiết lập Traffic Control cho bandwidth limiting
setup_traffic_control() {
    info_message "Thiết lập Traffic Control..."
    
    local interface=$(ip -o -4 route show to default | awk '{print $5}')
    
    # Remove existing rules
    tc qdisc del dev "$interface" root 2>/dev/null
    
    # Add root qdisc
    tc qdisc add dev "$interface" root handle 1: htb default 10
    tc class add dev "$interface" parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit
    tc class add dev "$interface" parent 1:1 classid 1:10 htb rate 1000mbit ceil 1000mbit
    
    success_message "Traffic Control đã được thiết lập"
}

# Tạo user proxy ban đầu
create_initial_user() {
    info_message "Tạo user proxy ban đầu..."
    
    # Generate random credentials
    local username=$(generate_random_string 8)
    local password=$(generate_random_string 12)
    
    # Add to Squid password file
    htpasswd -b /etc/squid/passwd "$username" "$password"
    
    # Add to database
    sqlite3 "$DB_PATH" "INSERT INTO users (username, password) VALUES ('$username', '$password');"
    
    # Save proxy information
    local server_ip=$(get_server_ip)
    {
        echo "============================================="
        echo "Proxy Credentials (Created: $(date '+%Y-%m-%d %H:%M:%S'))"
        echo "============================================="
        echo "Username: $username"
        echo "Password: $password"
        echo "Proxy IP: $server_ip"
        echo "Port: $port"
        echo "============================================="
        echo "Proxy String: $username:$password@$server_ip:$port"
        echo "============================================="
    } > "$PROXY_INFO_FILE"
    
    chmod 600 "$PROXY_INFO_FILE"
    
    success_message "User proxy ban đầu đã được tạo"
    echo -e "\n${GREEN}Thông tin Proxy của bạn:${NC}"
    echo -e "Username: ${YELLOW}$username${NC}"
    echo -e "Password: ${YELLOW}$password${NC}"
    echo -e "Proxy IP: ${YELLOW}$server_ip${NC}"
    echo -e "Port: ${YELLOW}$port${NC}"
    echo -e "Proxy String: ${YELLOW}$username:$password@$server_ip:$port${NC}"
}

# Hàm cài đặt chính cho Squid proxy
install_squid_proxy() {
    info_message "Bắt đầu cài đặt Squid HTTP proxy server..."
    
    # Set default port if not specified
    if [[ -z "$port" ]]; then
        port="$PROXY_PORT"
    fi
    
    # Cleanup old installation
    cleanup_old_installation
    
    # Install dependencies
    install_dependencies
    
    # Setup database
    setup_database
    
    # Create configuration
    create_config
    
    # Setup systemd service
    setup_systemd_service
    
    # Setup networking
    setup_networking
    
    # Setup traffic control
    setup_traffic_control
    
    # Create initial user
    create_initial_user
    
    # Create cron job for log cleanup
    (crontab -l 2>/dev/null; echo "0 0 * * * find /var/log/squid -mtime +7 -type f -delete") | crontab -
    
    success_message "Cài đặt Squid proxy server hoàn tất!"
    
    info_message "Thông tin tài khoản proxy được lưu tại: $PROXY_INFO_FILE"
    info_message "Xem thông tin với lệnh: cat $PROXY_INFO_FILE"
    
    pause
}
