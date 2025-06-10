#!/usr/bin/env bash

# lib/user_management.sh
#
# Chứa các hàm quản lý người dùng proxy cho Squid HTTP Proxy
# Tác giả: akmaslov-dev (Dante version)
# Chuyển đổi sang Squid bởi: ThienTranJP

# Đường dẫn đến file proxy chung
PROXY_FILE="/etc/squid/proxy_list.txt"

# Đảm bảo các thư mục và file cần thiết tồn tại
ensure_proxy_dir() {
    # Tạo thư mục chứa file proxy nếu chưa tồn tại
    if [[ ! -d "/etc/squid" ]]; then
        mkdir -p /etc/squid
    fi
    
    # Tạo file proxy nếu chưa tồn tại
    if [[ ! -f "$PROXY_FILE" ]]; then
        touch "$PROXY_FILE"
        chmod 600 "$PROXY_FILE"
    fi

    # Tạo file passwd nếu chưa tồn tại
    if [[ ! -f "/etc/squid/passwd" ]]; then
        touch /etc/squid/passwd
        chmod 644 /etc/squid/passwd
    fi
}

# Thêm proxy vào file proxy chung
add_to_proxy_file() {
    local ip=$1
    local port=$2
    local username=$3
    local password=$4
    
    # Đảm bảo thư mục và file tồn tại
    ensure_proxy_dir
    
    # Kiểm tra xem proxy đã tồn tại chưa
    if grep -q "^$ip:$port:$username:" "$PROXY_FILE" 2>/dev/null; then
        # Cập nhật mật khẩu nếu proxy đã tồn tại
        sed -i "s|^$ip:$port:$username:.*|$ip:$port:$username:$password|" "$PROXY_FILE"
    else
        # Thêm proxy mới vào file
        echo "$ip:$port:$username:$password" >> "$PROXY_FILE"
    fi
    
    info_message "Đã thêm/cập nhật proxy $ip:$port:$username:$password vào file quản lý"
}

# Xóa proxy khỏi file proxy chung
remove_from_proxy_file() {
    local username=$1
    
    # Đảm bảo thư mục và file tồn tại
    ensure_proxy_dir
    
    # Kiểm tra xem proxy có tồn tại không
    if grep -q ":$username:" "$PROXY_FILE" 2>/dev/null; then
        # Xóa proxy khỏi file
        sed -i "/:$username:/d" "$PROXY_FILE"
        info_message "Đã xóa proxy với username $username khỏi file quản lý"
    else
        warning_message "Không tìm thấy proxy với username $username trong file quản lý"
    fi
}

# Hiển thị danh sách proxy user
list_proxy_users() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                  DANH SÁCH PROXY                                 ║${NC}"
    echo -e "${CYAN}╠═══════════════╦═════════════════════╦════════════╦══════════════╦═══════════════╣${NC}"
    echo -e "${CYAN}║ Username      ║ Password            ║ Status     ║ Bandwidth    ║ Usage         ║${NC}"
    echo -e "${CYAN}╠═══════════════╬═════════════════════╬════════════╬══════════════╬═══════════════╣${NC}"

    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" \
            "SELECT username, password, status, bandwidth_limit, data_quota, data_used 
             FROM users ORDER BY username;" | \
        while IFS='|' read -r username password status bandwidth_limit data_quota data_used; do
            # Tính toán usage
            local used_gb=$(( data_used / 1024 / 1024 / 1024 ))
            local quota_gb=$(( data_quota / 1024 / 1024 / 1024 ))
            local usage_display="${used_gb}GB"
            [ "$data_quota" -gt 0 ] && usage_display+="/${quota_gb}GB" || usage_display+="/∞"

            # Format bandwidth
            local bw_display="${bandwidth_limit}Mbit/s"
            [ "$bandwidth_limit" -eq 0 ] && bw_display="Không giới hạn"

            # Status color
            local status_color="$GREEN"
            [ "$status" = "quota_exceeded" ] && status_color="$RED"

            # Hiển thị thông tin
            printf "${CYAN}║${NC} %-13s ${CYAN}║${NC} %-19s ${CYAN}║${NC} ${status_color}%-10s${NC} ${CYAN}║${NC} %-12s ${CYAN}║${NC} %-13s ${CYAN}║${NC}\n" \
                "$username" "$password" "$status" "$bw_display" "$usage_display"
        done
    fi

    echo -e "${CYAN}╚═══════════════╩═════════════════════╩════════════╩══════════════╩═══════════════╝${NC}"

    # Thống kê hệ thống
    if [[ -f "$DB_PATH" ]]; then
        echo -e "\n${YELLOW}Thống kê Hệ thống:${NC}"
        echo -e "Tổng số User: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")"
        echo -e "User hoạt động: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='active';" 2>/dev/null || echo "0")"
        echo -e "Tổng dữ liệu sử dụng: $(sqlite3 "$DB_PATH" "SELECT SUM(data_used)/1024/1024/1024 FROM users;" 2>/dev/null || echo "0")GB"
        
        local server_ip=$(get_server_ip)
        local port=$(get_squid_port)
        echo -e "Server IP: $server_ip"
        echo -e "Proxy Port: $port"
        echo -e "Proxy Status: $(systemctl is-active squid 2>/dev/null || echo "Unknown")"
        echo -e "Server Uptime: $(uptime -p 2>/dev/null || echo "Unknown")"
    fi
    
    pause
}

# Hàm tạo proxy user và thêm vào database
create_proxy_user() {
    local username=$1
    local password=$2
    local bandwidth=$3
    local quota=$4
    
    # Kiểm tra đầu vào
    if [[ -z "$username" ]]; then
        error_message "Tên đăng nhập không được để trống"
        return 1
    fi
    
    # Kiểm tra user đã tồn tại trong database chưa
    if user_exists_in_db "$username"; then
        error_message "User $username đã tồn tại trong database"
        return 2
    fi
    
    # Thêm user vào Squid password file
    htpasswd -b /etc/squid/passwd "$username" "$password"
    
    # Thêm user vào database
    local quota_bytes=$((quota * 1024 * 1024 * 1024))
    sqlite3 "$DB_PATH" "INSERT INTO users (username, password, bandwidth_limit, data_quota) 
                        VALUES ('$username', '$password', $bandwidth, $quota_bytes);"
    
    # Thiết lập bandwidth limit nếu cần
    if [[ "$bandwidth" -gt 0 ]]; then
        setup_user_bandwidth_limit "$username" "$bandwidth"
    fi
    
    # Lấy thông tin server
    local server_ip=$(get_server_ip)
    local port=$(get_squid_port)
    
    # Thêm proxy vào file quản lý
    add_to_proxy_file "$server_ip" "$port" "$username" "$password"
    
    # Restart Squid để áp dụng thay đổi
    systemctl reload squid >/dev/null 2>&1
    
    # Hiển thị thông tin proxy
    success_message "Đã tạo proxy user:"
    echo -e "IP: ${YELLOW}$server_ip${NC}"
    echo -e "Port: ${YELLOW}$port${NC}"
    echo -e "Username: ${YELLOW}$username${NC}"
    echo -e "Password: ${YELLOW}$password${NC}"
    echo -e "Bandwidth Limit: ${YELLOW}${bandwidth}Mbit/s${NC}"
    echo -e "Data Quota: ${YELLOW}${quota}GB${NC}"
    echo ""
    echo -e "Proxy string: ${YELLOW}$username:$password@$server_ip:$port${NC}"
    
    return 0
}

# Thiết lập giới hạn bandwidth cho user
setup_user_bandwidth_limit() {
    local username=$1
    local bandwidth=$2
    
    # Tạo class ID từ username
    local class_id=$(echo "$username" | md5sum | cut -c1-4)
    local interface=$(ip -o -4 route show to default | awk '{print $5}')
    
    # Thêm class cho user
    tc class add dev "$interface" parent 1:1 classid "1:${class_id}" htb rate "${bandwidth}mbit" ceil "${bandwidth}mbit" 2>/dev/null
    tc filter add dev "$interface" protocol ip parent 1:0 prio 1 \
        u32 match ip dst 0.0.0.0/0 flowid "1:${class_id}" 2>/dev/null
    
    info_message "Đã thiết lập giới hạn bandwidth ${bandwidth}Mbit/s cho user $username"
}

# Thêm một proxy user mới
add_proxy_user() {
    info_message "Thêm proxy user mới"
    
    # Lấy tên đăng nhập mới
    read -p "Nhập tên cho proxy user mới: " -e -i proxyuser usernew
    echo ""
    
    # Kiểm tra đầu vào
    if [[ -z "$usernew" ]]; then
        error_message "Tên đăng nhập không được để trống"
        pause
        return 1
    fi
    
    # Kiểm tra định dạng username
    if [[ ! "$usernew" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_message "Tên đăng nhập chỉ được chứa chữ cái, số, dấu gạch dưới và dấu gạch ngang"
        pause
        return 1
    fi
    
    # Lấy mật khẩu hoặc tạo mật khẩu ngẫu nhiên
    read -p "Nhập mật khẩu (bỏ trống để tạo mật khẩu ngẫu nhiên): " -e passnew
    echo ""
    
    # Nếu mật khẩu trống, tạo mật khẩu ngẫu nhiên
    if [[ -z "$passnew" ]]; then
        passnew=$(generate_random_string 12)
        info_message "Mật khẩu được tạo ngẫu nhiên: $passnew"
    fi
    
    # Lấy giới hạn bandwidth
    read -p "Nhập giới hạn bandwidth (Mbit/s, 0 cho không giới hạn): " -e -i 0 bandwidth
    
    # Kiểm tra bandwidth hợp lệ
    if ! is_valid_number "$bandwidth"; then
        warning_message "Giới hạn bandwidth không hợp lệ, sử dụng mặc định 0 (không giới hạn)"
        bandwidth=0
    fi
    
    # Lấy quota dữ liệu
    read -p "Nhập quota dữ liệu (GB, 0 cho không giới hạn): " -e -i 0 quota
    
    # Kiểm tra quota hợp lệ
    if ! is_valid_number "$quota"; then
        warning_message "Quota dữ liệu không hợp lệ, sử dụng mặc định 0 (không giới hạn)"
        quota=0
    fi
    
    # Tạo proxy user
    create_proxy_user "$usernew" "$passnew" "$bandwidth" "$quota"
    
    pause
}

# Thêm ngẫu nhiên nhiều proxy
add_random_proxies() {
    info_message "Thêm ngẫu nhiên nhiều proxy"
    
    # Lấy số lượng proxy cần tạo
    read -p "Nhập số lượng proxy cần tạo: " -e -i 5 num_proxies
    
    # Kiểm tra đầu vào
    if ! is_valid_number "$num_proxies" || [ "$num_proxies" -lt 1 ]; then
        error_message "Số lượng proxy không hợp lệ"
        pause
        return 1
    fi
    
    # Lấy giới hạn bandwidth
    read -p "Nhập giới hạn bandwidth (Mbit/s, 0 cho không giới hạn): " -e -i 0 bandwidth
    
    # Kiểm tra bandwidth hợp lệ
    if ! is_valid_number "$bandwidth"; then
        warning_message "Giới hạn bandwidth không hợp lệ, sử dụng mặc định 0"
        bandwidth=0
    fi
    
    # Lấy quota dữ liệu
    read -p "Nhập quota dữ liệu (GB, 0 cho không giới hạn): " -e -i 0 quota
    
    # Kiểm tra quota hợp lệ
    if ! is_valid_number "$quota"; then
        warning_message "Quota dữ liệu không hợp lệ, sử dụng mặc định 0"
        quota=0
    fi
    
    info_message "Bắt đầu tạo $num_proxies proxy users..."
    
    # Lưu thông tin vào file
    echo "============= PROXY USERS MỚI =============" >> "$PROXY_INFO_FILE"
    echo "Tạo lúc: $(date '+%Y-%m-%d %H:%M:%S')" >> "$PROXY_INFO_FILE"
    echo "" >> "$PROXY_INFO_FILE"
    
    for ((i=1; i<=num_proxies; i++)); do
        # Tạo username và password ngẫu nhiên
        local username=$(generate_random_string 8)
        local password=$(generate_random_string 12)
        
        # Kiểm tra user đã tồn tại chưa
        while user_exists_in_db "$username"; do
            username=$(generate_random_string 8)
        done
        
        # Tạo proxy user
        if create_proxy_user "$username" "$password" "$bandwidth" "$quota"; then
            echo "Progress: $i/$num_proxies users created"
            
            # Lưu vào file thông tin
            local server_ip=$(get_server_ip)
            local port=$(get_squid_port)
            echo "$username:$password@$server_ip:$port" >> "$PROXY_INFO_FILE"
        else
            error_message "Không thể tạo user $username"
            ((i--))
        fi
    done
    
    echo "" >> "$PROXY_INFO_FILE"
    echo "=============================================" >> "$PROXY_INFO_FILE"
    
    success_message "Đã tạo thành công $num_proxies proxy users"
    
    pause
}

# Xóa một proxy user
delete_proxy_user() {
    info_message "Xóa proxy user"
    
    # Hiển thị danh sách user hiện có
    echo "Danh sách user hiện có:"
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "SELECT username FROM users ORDER BY username;" 2>/dev/null
    fi
    echo ""
    
    # Lấy tên user cần xóa
    read -p "Nhập tên user cần xóa: " username_to_delete
    
    # Kiểm tra đầu vào
    if [[ -z "$username_to_delete" ]]; then
        error_message "Tên user không được để trống"
        pause
        return 1
    fi
    
    # Kiểm tra user có tồn tại không
    if ! user_exists_in_db "$username_to_delete"; then
        error_message "User $username_to_delete không tồn tại"
        pause
        return 1
    fi
    
    # Xác nhận xóa
    read -p "Bạn có chắc chắn muốn xóa user '$username_to_delete'? (y/n): " -e -i n confirm
    
    if [[ "$confirm" != 'y' && "$confirm" != 'Y' ]]; then
        info_message "Đã hủy xóa user"
        pause
        return 0
    fi
    
    # Xóa user khỏi Squid password file
    htpasswd -D /etc/squid/passwd "$username_to_delete" 2>/dev/null
    
    # Xóa user khỏi database
    sqlite3 "$DB_PATH" "DELETE FROM users WHERE username='$username_to_delete';"
    sqlite3 "$DB_PATH" "DELETE FROM traffic_log WHERE username='$username_to_delete';"
    
    # Xóa bandwidth limits
    local class_id=$(echo "$username_to_delete" | md5sum | cut -c1-4)
    local interface=$(ip -o -4 route show to default | awk '{print $5}')
    tc filter del dev "$interface" parent 1:0 2>/dev/null
    tc class del dev "$interface" classid "1:${class_id}" 2>/dev/null
    
    # Xóa khỏi file proxy
    remove_from_proxy_file "$username_to_delete"
    
    # Reload Squid
    systemctl reload squid >/dev/null 2>&1
    
    success_message "Đã xóa user $username_to_delete thành công"
    
    pause
}

# Xóa toàn bộ proxy users
delete_all_proxy_users() {
    warning_message "Xóa toàn bộ proxy users"
    
    # Xác nhận xóa
    read -p "CẢNH BÁO: Bạn có chắc chắn muốn xóa TẤT CẢ proxy users? (y/n): " -e -i n confirm
    
    if [[ "$confirm" != 'y' && "$confirm" != 'Y' ]]; then
        info_message "Đã hủy xóa tất cả users"
        pause
        return 0
    fi
    
    # Xác nhận lần 2
    read -p "Xác nhận lần cuối: Nhập 'DELETE' để xóa tất cả users: " final_confirm
    
    if [[ "$final_confirm" != "DELETE" ]]; then
        info_message "Đã hủy xóa tất cả users"
        pause
        return 0
    fi
    
    # Xóa tất cả user khỏi database
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "DELETE FROM users;"
        sqlite3 "$DB_PATH" "DELETE FROM traffic_log;"
    fi
    
    # Xóa file password của Squid
    > /etc/squid/passwd
    
    # Xóa file proxy list
    > "$PROXY_FILE"
    
    # Xóa tất cả traffic control rules
    local interface=$(ip -o -4 route show to default | awk '{print $5}')
    tc qdisc del dev "$interface" root 2>/dev/null
    tc qdisc add dev "$interface" root handle 1: htb default 10
    tc class add dev "$interface" parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit
    tc class add dev "$interface" parent 1:1 classid 1:10 htb rate 1000mbit ceil 1000mbit
    
    # Reload Squid
    systemctl reload squid >/dev/null 2>&1
    
    success_message "Đã xóa tất cả proxy users thành công"
    
    pause
}

# Cập nhật giới hạn bandwidth cho user
update_user_bandwidth() {
    info_message "Cập nhật giới hạn bandwidth"
    
    # Hiển thị danh sách user
    echo "Danh sách user hiện có:"
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "SELECT username, bandwidth_limit FROM users ORDER BY username;" 2>/dev/null | \
        while IFS='|' read -r username bandwidth; do
            echo "  - $username (hiện tại: ${bandwidth}Mbit/s)"
        done
    fi
    echo ""
    
    # Lấy thông tin từ user
    read -p "Nhập tên user: " username
    read -p "Nhập giới hạn bandwidth mới (Mbit/s, 0 cho không giới hạn): " bandwidth
    
    # Kiểm tra đầu vào
    if [[ -z "$username" ]]; then
        error_message "Tên user không được để trống"
        pause
        return 1
    fi
    
    if ! is_valid_number "$bandwidth"; then
        error_message "Giới hạn bandwidth không hợp lệ"
        pause
        return 1
    fi
    
    # Kiểm tra user tồn tại
    if ! user_exists_in_db "$username"; then
        error_message "User $username không tồn tại"
        pause
        return 1
    fi
    
    # Cập nhật trong database
    sqlite3 "$DB_PATH" "UPDATE users SET bandwidth_limit=$bandwidth WHERE username='$username';"
    
    # Thiết lập lại bandwidth limit
    setup_user_bandwidth_limit "$username" "$bandwidth"
    
    success_message "Đã cập nhật giới hạn bandwidth cho user $username: ${bandwidth}Mbit/s"
    
    pause
}

# Cập nhật quota dữ liệu cho user
update_user_quota() {
    info_message "Cập nhật quota dữ liệu"
    
    # Hiển thị danh sách user
    echo "Danh sách user hiện có:"
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "SELECT username, data_quota/1024/1024/1024, data_used/1024/1024/1024 FROM users ORDER BY username;" 2>/dev/null | \
        while IFS='|' read -r username quota used; do
            echo "  - $username (quota: ${quota}GB, đã dùng: ${used}GB)"
        done
    fi
    echo ""
    
    # Lấy thông tin từ user
    read -p "Nhập tên user: " username
    read -p "Nhập quota dữ liệu mới (GB, 0 cho không giới hạn): " quota
    
    # Kiểm tra đầu vào
    if [[ -z "$username" ]]; then
        error_message "Tên user không được để trống"
        pause
        return 1
    fi
    
    if ! is_valid_number "$quota"; then
        error_message "Quota dữ liệu không hợp lệ"
        pause
        return 1
    fi
    
    # Kiểm tra user tồn tại
    if ! user_exists_in_db "$username"; then
        error_message "User $username không tồn tại"
        pause
        return 1
    fi
    
    # Cập nhật trong database
    local quota_bytes=$((quota * 1024 * 1024 * 1024))
    sqlite3 "$DB_PATH" "UPDATE users SET data_quota=$quota_bytes WHERE username='$username';"
    
    success_message "Đã cập nhật quota dữ liệu cho user $username: ${quota}GB"
    
    pause
}

# Xuất danh sách proxy
export_proxy_list() {
    info_message "Xuất danh sách proxy"
    
    local export_file="/root/proxy_export_$(date +%Y%m%d_%H%M%S).txt"
    
    # Đảm bảo thư mục tồn tại
    ensure_proxy_dir
    
    # Lấy thông tin server
    local server_ip=$(get_server_ip)
    local port=$(get_squid_port)
    
    # Xuất từ database
    if [[ -f "$DB_PATH" ]]; then
        echo "# Proxy List - Exported $(date '+%Y-%m-%d %H:%M:%S')" > "$export_file"
        echo "# Format: username:password@ip:port" >> "$export_file"
        echo "" >> "$export_file"
        
        sqlite3 "$DB_PATH" "SELECT username, password FROM users WHERE status='active' ORDER BY username;" 2>/dev/null | \
        while IFS='|' read -r username password; do
            echo "$username:$password@$server_ip:$port" >> "$export_file"
        done
    fi
    
    if [[ -f "$export_file" ]]; then
        success_message "Đã xuất danh sách proxy vào file: $export_file"
        
        # Hiển thị preview
        echo -e "\n${YELLOW}Preview (10 dòng đầu):${NC}"
        head -15 "$export_file"
        
        echo -e "\n${YELLOW}Tổng số proxy:${NC} $(grep -c "@" "$export_file" 2>/dev/null || echo "0")"
    else
        error_message "Không thể tạo file xuất"
    fi
    
    pause
}

# Hiển thị thống kê
show_statistics() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                THỐNG KÊ HỆ THỐNG                                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    if [[ -f "$DB_PATH" ]]; then
        # Thống kê tổng quan
        echo -e "\n${YELLOW}Thống kê Tổng quan:${NC}"
        echo -e "Tổng số Users: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")"
        echo -e "Users hoạt động: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='active';" 2>/dev/null || echo "0")"
        echo -e "Users vượt quota: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='quota_exceeded';" 2>/dev/null || echo "0")"
        echo -e "Tổng dữ liệu sử dụng: $(sqlite3 "$DB_PATH" "SELECT ROUND(SUM(data_used)/1024.0/1024.0/1024.0, 2) FROM users;" 2>/dev/null || echo "0")GB"
        
        # Top users theo usage
        echo -e "\n${YELLOW}Top 5 Users theo Usage:${NC}"
        sqlite3 "$DB_PATH" "SELECT username, ROUND(data_used/1024.0/1024.0/1024.0, 2) as used_gb 
                           FROM users ORDER BY data_used DESC LIMIT 5;" 2>/dev/null | \
        while IFS='|' read -r username used_gb; do
            echo "  - $username: ${used_gb}GB"
        done
        
        # Thống kê theo ngày
        echo -e "\n${YELLOW}Hoạt động hôm nay:${NC}"
        local today=$(date '+%Y-%m-%d')
        echo -e "Traffic hôm nay: $(sqlite3 "$DB_PATH" "SELECT ROUND(SUM(bytes_in + bytes_out)/1024.0/1024.0/1024.0, 2) 
                                                      FROM traffic_log WHERE DATE(timestamp) = '$today';" 2>/dev/null || echo "0")GB"
    fi
    
    # Thông tin hệ thống
    echo -e "\n${YELLOW}Thông tin Hệ thống:${NC}"
    echo -e "Server IP: $(get_server_ip)"
    echo -e "Proxy Port: $(get_squid_port)"
    echo -e "Squid Status: $(systemctl is-active squid 2>/dev/null || echo "Unknown")"
    echo -e "System Uptime: $(uptime -p 2>/dev/null || echo "Unknown")"
    echo -e "Disk Usage: $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}' 2>/dev/null || echo "Unknown")"
    echo -e "Memory Usage: $(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}' 2>/dev/null || echo "Unknown")"
    
    pause
}

# Backup database
backup_database() {
    info_message "Backup database"
    
    if [[ ! -f "$DB_PATH" ]]; then
        error_message "Database không tồn tại"
        pause
        return 1
    fi
    
    local backup_file="/root/proxy_backup_$(date +%Y%m%d_%H%M%S).db"
    
    if cp "$DB_PATH" "$backup_file"; then
        success_message "Đã backup database vào: $backup_file"
        
        # Hiển thị thông tin backup
        echo -e "Kích thước: $(du -h "$backup_file" | cut -f1)"
        echo -e "Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    else
        error_message "Không thể backup database"
    fi
    
    pause
}

# Kiểm tra trạng thái dịch vụ
check_service_status() {
    info_message "Kiểm tra trạng thái dịch vụ"
    
    echo -e "\n${YELLOW}Trạng thái Squid:${NC}"
    systemctl status squid --no-pager
    
    echo -e "\n${YELLOW}Cổng đang lắng nghe:${NC}"
    netstat -tuln | grep ":$(get_squid_port) "
    
    echo -e "\n${YELLOW}Processes liên quan:${NC}"
    ps aux | grep squid | grep -v grep
    
    pause
}

# Khởi động lại dịch vụ
restart_service() {
    info_message "Khởi động lại dịch vụ Squid"
    
    if systemctl restart squid; then
        sleep 3
        if systemctl is-active --quiet squid; then
            success_message "Dịch vụ Squid đã được khởi động lại thành công"
        else
            error_message "Dịch vụ Squid không thể khởi động"
        fi
    else
        error_message "Không thể khởi động lại dịch vụ Squid"
    fi
    
    pause
}

