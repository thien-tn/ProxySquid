#!/bin/bash

# Script kiểm tra cài đặt Squid trên Ubuntu
# Tác giả: Squid Proxy Manager
# Mô tả: Test script để kiểm tra quá trình cài đặt dependencies

# Import common functions
source "$(dirname "$0")/lib/common.sh"

# Hàm kiểm tra hệ điều hành
check_ubuntu() {
    info_message "Kiểm tra hệ điều hành..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "OS: $NAME"
        echo "Version: $VERSION"
        echo "ID: $ID"
        echo "Codename: $VERSION_CODENAME"
        
        if [[ "$ID" == "ubuntu" ]]; then
            success_message "Đang chạy trên Ubuntu"
            return 0
        else
            warning_message "Không phải Ubuntu: $ID"
            return 1
        fi
    else
        error_message "Không thể xác định hệ điều hành"
        return 1
    fi
}

# Hàm kiểm tra quyền root
check_root_permission() {
    info_message "Kiểm tra quyền root..."
    
    if [[ $EUID -eq 0 ]]; then
        success_message "Đang chạy với quyền root"
        return 0
    else
        error_message "Cần quyền root để chạy script này"
        echo "Chạy: sudo $0"
        return 1
    fi
}

# Hàm kiểm tra network connectivity
check_network() {
    info_message "Kiểm tra kết nối mạng..."
    
    # Kiểm tra DNS
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        success_message "Kết nối internet: OK"
    else
        error_message "Không có kết nối internet"
        return 1
    fi
    
    # Kiểm tra DNS resolution
    if nslookup archive.ubuntu.com >/dev/null 2>&1; then
        success_message "DNS resolution: OK"
    else
        warning_message "Có vấn đề với DNS resolution"
    fi
    
    # Kiểm tra Ubuntu repositories
    if curl -s --connect-timeout 10 http://archive.ubuntu.com >/dev/null; then
        success_message "Ubuntu repositories: OK"
    else
        warning_message "Không thể kết nối Ubuntu repositories"
    fi
}

# Hàm kiểm tra disk space
check_disk_space() {
    info_message "Kiểm tra dung lượng disk..."
    
    local available=$(df / | awk 'NR==2 {print $4}')
    local available_gb=$((available / 1024 / 1024))
    
    echo "Dung lượng khả dụng: ${available_gb}GB"
    
    if [[ $available_gb -gt 2 ]]; then
        success_message "Đủ dung lượng disk"
        return 0
    else
        error_message "Không đủ dung lượng disk (cần ít nhất 2GB)"
        return 1
    fi
}

# Hàm test APT system
test_apt_system() {
    info_message "Kiểm tra APT system..."
    
    # Kill any running apt processes
    pkill -f apt 2>/dev/null || true
    pkill -f dpkg 2>/dev/null || true
    sleep 2
    
    # Check lock files
    for lock_file in "/var/lib/dpkg/lock" "/var/lib/dpkg/lock-frontend" "/var/cache/apt/archives/lock"; do
        if [[ -f "$lock_file" ]]; then
            if fuser "$lock_file" >/dev/null 2>&1; then
                warning_message "$lock_file is locked"
                # Try to wait
                sleep 10
                if fuser "$lock_file" >/dev/null 2>&1; then
                    error_message "APT system is locked"
                    return 1
                fi
            fi
        fi
    done
    
    # Test apt update
    info_message "Test apt update..."
    export DEBIAN_FRONTEND=noninteractive
    
    if timeout 60 apt-get update >/dev/null 2>&1; then
        success_message "APT update: OK"
    else
        error_message "APT update failed"
        return 1
    fi
    
    # Test package installation
    info_message "Test package installation..."
    if timeout 60 apt-get install -y --dry-run curl >/dev/null 2>&1; then
        success_message "Package installation test: OK"
    else
        warning_message "Package installation test failed"
    fi
}

# Hàm test cài đặt dependencies cơ bản
test_basic_packages() {
    info_message "Test cài đặt packages cơ bản..."
    
    local test_packages=("curl" "wget" "net-tools")
    
    for package in "${test_packages[@]}"; do
        info_message "Test cài đặt $package..."
        
        if timeout 120 apt-get install -y "$package" >/dev/null 2>&1; then
            success_message "Cài đặt $package: OK"
        else
            error_message "Không thể cài đặt $package"
            return 1
        fi
    done
}

# Hàm test cài đặt Squid packages
test_squid_packages() {
    info_message "Test cài đặt Squid packages..."
    
    local squid_packages=("squid" "apache2-utils" "sqlite3")
    
    for package in "${squid_packages[@]}"; do
        info_message "Test cài đặt $package..."
        
        if timeout 300 apt-get install -y "$package" >/dev/null 2>&1; then
            success_message "Cài đặt $package: OK"
            
            # Verify installation
            if dpkg -l | grep -q "^ii.*$package "; then
                success_message "Verification $package: OK"
            else
                warning_message "$package có thể chưa được cài đặt hoàn toàn"
            fi
        else
            error_message "Không thể cài đặt $package"
            return 1
        fi
    done
}

# Hàm chính
main() {
    clear
    echo -e "${GREEN}=========================${NC}"
    echo -e "${GREEN} TEST CÀI ĐẶT SQUID${NC}"
    echo -e "${GREEN}=========================${NC}\n"
    
    # Kiểm tra các điều kiện cơ bản
    check_root_permission || exit 1
    check_ubuntu || exit 1
    check_network || exit 1
    check_disk_space || exit 1
    
    # Test APT system
    test_apt_system || exit 1
    
    # Test cài đặt packages
    test_basic_packages || exit 1
    test_squid_packages || exit 1
    
    echo -e "\n${GREEN}=========================${NC}"
    success_message "TẤT CẢ TESTS THÀNH CÔNG!"
    echo -e "${GREEN}=========================${NC}\n"
    
    info_message "Bây giờ bạn có thể chạy cài đặt Squid chính thức:"
    echo "./install.sh"
}

# Chạy script
main "$@" 