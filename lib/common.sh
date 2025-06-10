#!/usr/bin/env bash

# lib/common.sh
#
# Chứa các hàm dùng chung cho toàn bộ hệ thống Squid HTTP Proxy
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Biến toàn cục
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
CONFIG_DIR="$SCRIPT_DIR/config"
LIB_DIR="$SCRIPT_DIR/lib"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DB_PATH="/var/lib/proxy-manager/proxy.db"
PROXY_INFO_FILE="/root/proxy_info.txt"
LOG_FILE="/var/log/proxy-manager.log"
PROXY_PORT=8080

# Màu sắc cho terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Hàm hiển thị thông báo thành công
# $1: Nội dung thông báo
success_message() {
    echo -e "${GREEN}[✓] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE"
}

# Hàm hiển thị thông báo lỗi
# $1: Nội dung thông báo
error_message() {
    echo -e "${RED}[✗] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

# Hàm hiển thị thông báo cảnh báo
# $1: Nội dung thông báo
warning_message() {
    echo -e "${YELLOW}[!] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

# Hàm hiển thị thông báo thông tin
# $1: Nội dung thông báo
info_message() {
    echo -e "${BLUE}[i] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE"
}

# Hàm tạm dừng cho đến khi người dùng nhấn Enter
pause() {
    echo ""
    read -p "Nhấn Enter để tiếp tục..."
}

# Hàm kiểm tra xem Squid đã được cài đặt chưa
is_squid_installed() {
    [[ -e /etc/squid/squid.conf ]] && command -v squid >/dev/null 2>&1 && return 0 || return 1
}

# Hàm lấy danh sách proxy user từ database
get_proxy_users() {
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "SELECT username FROM users WHERE status='active';" 2>/dev/null
    fi
}

# Hàm kiểm tra xem user có tồn tại trong database không
# $1: Tên user cần kiểm tra
user_exists_in_db() {
    if [[ -f "$DB_PATH" ]]; then
        local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE username='$1';" 2>/dev/null)
        [[ "$count" -gt 0 ]] && return 0 || return 1
    else
        return 1
    fi
}

# Hàm kiểm tra xem user có tồn tại trong hệ thống không
# $1: Tên user cần kiểm tra
user_exists() {
    getent passwd "$1" > /dev/null 2>&1
}

# Hàm tạo chuỗi ngẫu nhiên
# $1: Độ dài chuỗi (mặc định là 8)
generate_random_string() {
    local length=${1:-8}
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1
}

# Hàm lấy địa chỉ IP của máy chủ
get_server_ip() {
    curl -s ifconfig.me || wget -qO- ifconfig.me || hostname -I | awk '{print $1}'
}

# Hàm lấy port từ file cấu hình Squid
get_squid_port() {
    if [[ -f /etc/squid/squid.conf ]]; then
        grep -oP 'http_port\s+\K[0-9]+' /etc/squid/squid.conf | head -1
    else
        echo "$PROXY_PORT" # Mặc định nếu không tìm thấy
    fi
}

# Hàm kiểm tra input là số hợp lệ
# $1: Giá trị cần kiểm tra
# $2: Giá trị nhỏ nhất (tùy chọn)
# $3: Giá trị lớn nhất (tùy chọn)
is_valid_number() {
    local value=$1
    local min=${2:-0}
    local max=${3:-999999}
    
    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]; then
        return 0
    else
        return 1
    fi
}

# Hàm kiểm tra cổng hợp lệ
# $1: Cổng cần kiểm tra
is_valid_port() {
    local port=$1
    
    # Kiểm tra cổng có phải là số nguyên dương và nằm trong khoảng hợp lệ (1-65535)
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Hàm kiểm tra cổng đã được sử dụng chưa
# $1: Cổng cần kiểm tra
is_port_in_use() {
    local port=$1
    
    # Kiểm tra cổng có đang được sử dụng không
    if command -v ss >/dev/null 2>&1; then
        # Sử dụng ss nếu có
        if ss -tuln | grep -q ":$port "; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        # Sử dụng netstat nếu không có ss
        if netstat -tuln | grep -q ":$port "; then
            return 0
        fi
    else
        # Nếu không có công cụ nào, giả định cổng không được sử dụng
        warning_message "Không thể kiểm tra cổng đã được sử dụng chưa. Giả định cổng không được sử dụng."
        return 1
    fi
    
    return 1
}

# Hàm thiết lập database SQLite
setup_database() {
    info_message "Thiết lập database SQLite..."
    
    mkdir -p "$(dirname "$DB_PATH")"
    
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    password TEXT,
    bandwidth_limit INTEGER DEFAULT 0,
    data_quota INTEGER DEFAULT 0,
    data_used INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_active DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS traffic_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    bytes_in INTEGER DEFAULT 0,
    bytes_out INTEGER DEFAULT 0,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(username) REFERENCES users(username)
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_traffic_username ON traffic_log(username);
EOF

    chmod 600 "$DB_PATH"
    success_message "Database đã được thiết lập"
}

# Hàm kiểm tra và mở cổng trong tường lửa
# $1: Số cổng cần mở
open_firewall_port() {
    local port=$1
    
    # Kiểm tra và mở cổng với UFW
    if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow "$port"/tcp
        success_message "Đã mở cổng $port trong UFW."
    fi
    
    # Kiểm tra và mở cổng với iptables
    if command -v iptables >/dev/null 2>&1; then
        if ! sudo iptables -L | grep -q "ACCEPT.*tcp.*dpt:$port"; then
            sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            success_message "Đã mở cổng $port trong iptables."
        fi
    fi
}

# Hàm cập nhật thống kê sử dụng cho user
# $1: username
# $2: bytes_in
# $3: bytes_out
update_user_traffic() {
    local username=$1
    local bytes_in=$2
    local bytes_out=$3
    
    if [[ -f "$DB_PATH" ]]; then
        # Cập nhật tổng dữ liệu đã sử dụng
        local total_bytes=$((bytes_in + bytes_out))
        sqlite3 "$DB_PATH" "UPDATE users SET data_used = data_used + $total_bytes, last_active = CURRENT_TIMESTAMP WHERE username='$username';"
        
        # Thêm log traffic
        sqlite3 "$DB_PATH" "INSERT INTO traffic_log (username, bytes_in, bytes_out) VALUES ('$username', $bytes_in, $bytes_out);"
    fi
}
