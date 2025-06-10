#!/usr/bin/env bash

# lib/check_environment.sh
#
# Chứa các hàm kiểm tra môi trường hệ thống cho Squid HTTP Proxy
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Kiểm tra quyền root
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error_message "Script này cần được chạy với quyền root"
        exit 2
    fi
    success_message "Đang chạy với quyền root"
}

# Kiểm tra shell bash
check_bash() {
    if readlink /proc/$$/exe | grep -qs "dash"; then
        error_message "Script này cần được chạy với bash, không phải sh"
        exit 1
    fi
    success_message "Đang sử dụng bash shell"
}

# Phát hiện hệ điều hành
detect_os() {
    if [[ -e /etc/debian_version ]]; then
        export OStype="deb"
        success_message "Phát hiện hệ điều hành: Debian/Ubuntu"
    elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
        export OStype="centos"
        success_message "Phát hiện hệ điều hành: CentOS/RHEL"
    else
        error_message "Script này chỉ hỗ trợ Debian, Ubuntu hoặc CentOS"
        exit 3
    fi
}

# Phát hiện giao diện mạng
detect_network_interface() {
    export interface="$(ip -o -4 route show to default | awk '{print $5}')"
    
    # Kiểm tra xem giao diện có tồn tại không
    if [[ -n "$interface" && -d "/sys/class/net/$interface" ]]; then
        success_message "Phát hiện giao diện mạng: $interface"
    else
        error_message "Không thể phát hiện giao diện mạng"
        exit 4
    fi
    
    # Lấy địa chỉ IP
    export hostname=$(hostname -I | awk '{print $1}')
    success_message "Địa chỉ IP máy chủ: $hostname"
}

# Kiểm tra các gói phụ thuộc cần thiết
check_dependencies() {
    local missing_packages=()
    
    # Danh sách các gói cần thiết cho Squid
    local required_packages=(
        "squid"
        "sqlite3" 
        "apache2-utils"
        "iptables"
        "iproute2"
        "net-tools"
        "curl"
        "wget"
    )
    
    info_message "Đang kiểm tra các gói phụ thuộc..."
    
    for package in "${required_packages[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
            warning_message "Thiếu gói: $package"
        else
            success_message "Đã cài đặt: $package"
        fi
    done
    
    # Kiểm tra các gói hệ thống
    if [[ "$OStype" == "debian" ]]; then
        local system_packages=("build-essential" "pkg-config")
        for package in "${system_packages[@]}"; do
            if ! dpkg -l | grep -q "^ii.*$package"; then
                missing_packages+=("$package")
                warning_message "Thiếu gói hệ thống: $package"
            fi
        done
    elif [[ "$OStype" == "centos" ]]; then
        local system_packages=("gcc" "gcc-c++" "make" "pkgconfig")
        for package in "${system_packages[@]}"; do
            if ! rpm -q "$package" >/dev/null 2>&1; then
                missing_packages+=("$package")
                warning_message "Thiếu gói hệ thống: $package"
            fi
        done
    fi
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        success_message "Tất cả các gói phụ thuộc đều đã được cài đặt"
        return 0
    else
        error_message "Thiếu ${#missing_packages[@]} gói phụ thuộc"
        return 1
    fi
}

# Kiểm tra bộ nhớ và tài nguyên hệ thống
check_system_resources() {
    info_message "Đang kiểm tra tài nguyên hệ thống..."
    
    # Kiểm tra RAM
    local total_ram=$(free -m | awk 'NR==2{print $2}')
    local available_ram=$(free -m | awk 'NR==2{print $7}')
    
    echo "Tổng RAM: ${total_ram}MB"
    echo "RAM khả dụng: ${available_ram}MB"
    
    if [[ $total_ram -lt 512 ]]; then
        warning_message "RAM thấp (dưới 512MB). Squid có thể hoạt động chậm."
    elif [[ $total_ram -lt 1024 ]]; then
        info_message "RAM vừa đủ (${total_ram}MB). Squid sẽ hoạt động bình thường."
    else
        success_message "RAM đầy đủ (${total_ram}MB). Squid sẽ hoạt động tốt."
    fi
    
    # Kiểm tra dung lượng ổ cứng
    local root_usage=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
    local available_space=$(df -h / | awk 'NR==2{print $4}')
    
    echo "Dung lượng ổ cứng khả dụng: $available_space"
    echo "Đã sử dụng: ${root_usage}%"
    
    if [[ $root_usage -gt 90 ]]; then
        warning_message "Ổ cứng gần đầy (${root_usage}%). Cần giải phóng dung lượng."
    elif [[ $root_usage -gt 80 ]]; then
        info_message "Ổ cứng đang được sử dụng nhiều (${root_usage}%)."
    else
        success_message "Ổ cứng còn đủ dung lượng (${root_usage}% đã sử dụng)."
    fi
    
    # Kiểm tra CPU
    local cpu_cores=$(nproc)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    echo "Số lõi CPU: $cpu_cores"
    echo "Load average: $load_avg"
    
    if (( $(echo "$load_avg > $cpu_cores" | bc -l) )); then
        warning_message "Hệ thống đang tải cao (load: $load_avg, cores: $cpu_cores)"
    else
        success_message "Hệ thống hoạt động bình thường (load: $load_avg)"
    fi
}

# Kiểm tra kết nối mạng
check_network_connectivity() {
    info_message "Đang kiểm tra kết nối mạng..."
    
    # Kiểm tra kết nối internet
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        success_message "Kết nối internet hoạt động bình thường"
    else
        error_message "Không có kết nối internet"
        return 1
    fi
    
    # Kiểm tra DNS
    if nslookup google.com >/dev/null 2>&1; then
        success_message "Phân giải DNS hoạt động bình thường"
    else
        warning_message "Có vấn đề với phân giải DNS"
    fi
    
    # Kiểm tra port 8080 (port mặc định của Squid)
    if netstat -tuln 2>/dev/null | grep -q ":8080 "; then
        warning_message "Port 8080 đã được sử dụng"
    else
        success_message "Port 8080 khả dụng"
    fi
    
    return 0
}

# Kiểm tra quyền và bảo mật
check_permissions() {
    info_message "Đang kiểm tra quyền và bảo mật..."
    
    # Kiểm tra quyền root
    if [[ $EUID -ne 0 ]]; then
        error_message "Script cần chạy với quyền root"
        return 1
    else
        success_message "Đang chạy với quyền root"
    fi
    
    # Kiểm tra SELinux (nếu có)
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce 2>/dev/null)
        if [[ "$selinux_status" == "Enforcing" ]]; then
            warning_message "SELinux đang được bật (Enforcing). Có thể cần cấu hình thêm."
        elif [[ "$selinux_status" == "Permissive" ]]; then
            info_message "SELinux ở chế độ Permissive"
        else
            info_message "SELinux bị tắt"
        fi
    fi
    
    # Kiểm tra UFW firewall
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -1)
        info_message "UFW status: $ufw_status"
    fi
    
    # Kiểm tra thư mục cần thiết
    local required_dirs=(
        "/etc/squid"
        "/var/log/squid"
        "/var/spool/squid"
        "/var/cache/squid"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            success_message "Thư mục tồn tại: $dir"
        else
            info_message "Thư mục chưa tồn tại (sẽ được tạo): $dir"
        fi
    done
    
    return 0
}

# Kiểm tra cấu hình tường lửa
check_firewall() {
    info_message "Đang kiểm tra cấu hình tường lửa..."
    
    # Kiểm tra iptables
    if command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(iptables -L | wc -l)
        info_message "Số rules iptables: $iptables_rules"
        
        # Kiểm tra xem port 8080 có được mở không
        if iptables -L INPUT -n | grep -q "8080"; then
            success_message "Port 8080 đã được cấu hình trong iptables"
        else
            warning_message "Port 8080 chưa được cấu hình trong iptables"
        fi
    else
        warning_message "iptables không có sẵn"
    fi
    
    # Kiểm tra UFW
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "8080"; then
            success_message "Port 8080 đã được mở trong UFW"
        else
            warning_message "Port 8080 chưa được mở trong UFW"
        fi
    fi
}

# Kiểm tra tất cả các thành phần môi trường
check_all_environment() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                          KIỂM TRA MÔI TRƯỜNG HỆ THỐNG                   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    
    local errors=0
    
    # Kiểm tra hệ điều hành
    detect_os
    
    # Kiểm tra tài nguyên hệ thống
    if ! check_system_resources; then
        ((errors++))
    fi
    
    echo ""
    
    # Kiểm tra kết nối mạng
    if ! check_network_connectivity; then
        ((errors++))
    fi
    
    echo ""
    
    # Kiểm tra quyền
    if ! check_permissions; then
        ((errors++))
    fi
    
    echo ""
    
    # Kiểm tra tường lửa
    check_firewall
    
    echo ""
    
    # Kiểm tra phụ thuộc
    if ! check_dependencies; then
        ((errors++))
    fi
    
    echo ""
    
    if [[ $errors -eq 0 ]]; then
        success_message "Môi trường hệ thống đã sẵn sàng cho việc cài đặt Squid"
        return 0
    else
        error_message "Phát hiện $errors vấn đề trong môi trường hệ thống"
        return 1
    fi
}
